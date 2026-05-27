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
const nested_unit_program = boundary.program("evidence-nested-unit", struct {}, struct {
    pub const compiled_plan = unitPlan();
    pub const nested_with_targets = .{boundary.ir.NestedWithTarget{
        .metadata = "unit-target",
        .function_index = 0,
    }};
});

const Evidence = Program.Evidence;

const closure_fixture_semantic = boundary.ir.builder.semantic;
const closure_fixture_handlers = struct {};
const closure_approval_protocol = boundary.ir.schema.Protocol(.{
    .label = "approval",
    .ops = .{boundary.ir.schema.transform("request", []const u8, i32)},
});
const closure_approval_rows = closure_approval_protocol.Rows(closure_fixture_handlers, .{ .requirement_index = 0, .first_op = 0 });
const closure_approval_request_op = closure_approval_rows.op("request");
const closure_source_compiled = closure_fixture_semantic.finish(.{
    .label = "evidence-closure-source",
    .ir_hash = 0xC105E501,
    .entry = "run",
    .requirements = &.{closure_approval_rows.requirement},
    .ops = &closure_approval_rows.ops,
    .functions = .{.{
        .symbol_name = "run",
        .requirements = closure_fixture_semantic.span(0, 1),
        .params = .{},
        .locals = .{
            closure_fixture_semantic.local("payload", []const u8),
            closure_fixture_semantic.local("decision", i32),
        },
        .result = i32,
        .blocks = .{.{
            .name = "entry",
            .instructions = .{
                closure_fixture_semantic.constString("payload", "deploy-prod"),
                closure_fixture_semantic.call(closure_approval_request_op, .{ .dst = "decision", .payload = "payload", .label = "approval.request" }),
            },
            .terminator = closure_fixture_semantic.returnValue("decision"),
        }},
    }},
}) catch |err| @compileError("invalid closure source fixture: " ++ @errorName(err));
const closure_source_program = boundary.program("evidence-closure-source", closure_fixture_handlers, struct {
    pub const site_metadata = closure_source_compiled.site_metadata;
    pub const compiled_plan = closure_source_compiled.plan;
});
const closure_approval_request = closure_source_program.protocol.operationSite("approval", "request", 0);
const closure_dual_protocol = boundary.ir.schema.Protocol(.{
    .label = "approval-dual",
    .ops = .{
        boundary.ir.schema.transform("first", []const u8, i32),
        boundary.ir.schema.transform("second", []const u8, i32),
    },
});
const closure_dual_rows = closure_dual_protocol.Rows(closure_fixture_handlers, .{ .requirement_index = 0, .first_op = 0 });
const closure_dual_first_op = closure_dual_rows.op("first");
const closure_dual_second_op = closure_dual_rows.op("second");
const closure_dual_world_port_compiled = closure_fixture_semantic.finish(.{
    .label = "evidence-closure-dual-world-port",
    .ir_hash = 0xC105E508,
    .entry = "run",
    .requirements = &.{closure_dual_rows.requirement},
    .ops = &closure_dual_rows.ops,
    .functions = .{.{
        .symbol_name = "run",
        .requirements = closure_fixture_semantic.span(0, 1),
        .params = .{},
        .locals = .{
            closure_fixture_semantic.local("payload", []const u8),
            closure_fixture_semantic.local("first", i32),
            closure_fixture_semantic.local("second", i32),
        },
        .result = i32,
        .blocks = .{.{
            .name = "entry",
            .instructions = .{
                closure_fixture_semantic.constString("payload", "deploy-prod"),
                closure_fixture_semantic.call(closure_dual_first_op, .{ .dst = "first", .payload = "payload", .label = "approval-dual.first" }),
                closure_fixture_semantic.call(closure_dual_second_op, .{ .dst = "second", .payload = "payload", .label = "approval-dual.second" }),
            },
            .terminator = closure_fixture_semantic.returnValue("second"),
        }},
    }},
}) catch |err| @compileError("invalid dual world-port closure fixture: " ++ @errorName(err));
const closure_dual_world_port_program = boundary.program("evidence-closure-dual-world-port", closure_fixture_handlers, struct {
    pub const site_metadata = closure_dual_world_port_compiled.site_metadata;
    pub const compiled_plan = closure_dual_world_port_compiled.plan;
});
const closure_dual_first = closure_dual_world_port_program.protocol.operationSite("approval-dual", "first", 0);
const closure_dual_second = closure_dual_world_port_program.protocol.operationSite("approval-dual", "second", 0);
const closure_multi_yield_compiled = closure_fixture_semantic.finish(.{
    .label = "evidence-closure-multi-yield",
    .ir_hash = 0xC105E507,
    .entry = "run",
    .requirements = &.{closure_approval_rows.requirement},
    .ops = &closure_approval_rows.ops,
    .functions = .{.{
        .symbol_name = "run",
        .requirements = closure_fixture_semantic.span(0, 1),
        .params = .{},
        .locals = .{
            closure_fixture_semantic.local("payload", []const u8),
            closure_fixture_semantic.local("first", i32),
            closure_fixture_semantic.local("second", i32),
        },
        .result = i32,
        .blocks = .{.{
            .name = "entry",
            .instructions = .{
                closure_fixture_semantic.constString("payload", "deploy-prod"),
                closure_fixture_semantic.call(closure_approval_request_op, .{ .dst = "first", .payload = "payload", .label = "approval.request.first" }),
                closure_fixture_semantic.call(closure_approval_request_op, .{ .dst = "second", .payload = "payload", .label = "approval.request.second" }),
            },
            .terminator = closure_fixture_semantic.returnValue("second"),
        }},
    }},
}) catch |err| @compileError("invalid multi-yield closure fixture: " ++ @errorName(err));
const closure_multi_yield_program = boundary.program("evidence-closure-multi-yield", closure_fixture_handlers, struct {
    pub const site_metadata = closure_multi_yield_compiled.site_metadata;
    pub const compiled_plan = closure_multi_yield_compiled.plan;
});
const closure_handler_compiled = closure_fixture_semantic.finish(.{
    .label = "evidence-closure-handler",
    .ir_hash = 0xC105E502,
    .entry = "run",
    .functions = .{.{
        .symbol_name = "run",
        .params = .{closure_fixture_semantic.param("payload", []const u8)},
        .locals = .{closure_fixture_semantic.local("decision", i32)},
        .result = i32,
        .blocks = .{.{
            .name = "entry",
            .instructions = .{closure_fixture_semantic.constI32("decision", 1)},
            .terminator = closure_fixture_semantic.returnValue("decision"),
        }},
    }},
}) catch |err| @compileError("invalid closure handler fixture: " ++ @errorName(err));
const closure_handler_program = boundary.program("evidence-closure-handler", struct {}, struct {
    pub const compiled_plan = closure_handler_compiled.plan;
});
const closure_recursive_handler_compiled = closure_fixture_semantic.finish(.{
    .label = "evidence-closure-recursive-handler",
    .ir_hash = 0xC105E506,
    .entry = "run",
    .requirements = &.{closure_approval_rows.requirement},
    .ops = &closure_approval_rows.ops,
    .functions = .{.{
        .symbol_name = "run",
        .requirements = closure_fixture_semantic.span(0, 1),
        .params = .{closure_fixture_semantic.param("payload", []const u8)},
        .locals = .{closure_fixture_semantic.local("decision", i32)},
        .result = i32,
        .blocks = .{.{
            .name = "entry",
            .instructions = .{
                closure_fixture_semantic.call(closure_approval_request_op, .{ .dst = "decision", .payload = "payload", .label = "approval.request" }),
            },
            .terminator = closure_fixture_semantic.returnValue("decision"),
        }},
    }},
}) catch |err| @compileError("invalid recursive closure handler fixture: " ++ @errorName(err));
const closure_recursive_handler_program = boundary.program("evidence-closure-recursive-handler", closure_fixture_handlers, struct {
    pub const site_metadata = closure_recursive_handler_compiled.site_metadata;
    pub const compiled_plan = closure_recursive_handler_compiled.plan;
});
const closure_approval_decl = closure_source_program.Exchange.ProviderHandler.program(.{
    .label = "approval-program-handler",
    .op = closure_approval_request,
    .program = closure_handler_program,
    .map_request = .payload_to_args,
    .map_result = .result_to_resume,
});
const closure_harness = closure_source_program.Exchange.ProviderHarness(.{
    .label = "approval-program-provider",
    .provider_fingerprint = @as(?u64, 0xC105E503),
    .entries = .{closure_approval_decl},
});

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
    try std.testing.expectEqual(@as(u32, 2), Program.boundary_static_treaty_plan_fingerprint_version);
    try std.testing.expectEqual(Program.boundary_closure_policy_fingerprint_version, Evidence.domains.boundary_closure_policy.fingerprint_version);
    try std.testing.expectEqual(Program.boundary_closure_graph_fingerprint_version, Evidence.domains.boundary_closure_graph.fingerprint_version);
    try std.testing.expectEqual(Program.boundary_closure_report_fingerprint_version, Evidence.domains.boundary_closure_report.fingerprint_version);
    try std.testing.expectEqual(Program.boundary_closure_certificate_format_version, Evidence.domains.boundary_closure_certificate.format_version.?);
    try std.testing.expectEqual(Program.boundary_closure_certificate_fingerprint_version, Evidence.domains.boundary_closure_certificate.fingerprint_version);
    try std.testing.expectEqual(Program.boundary_world_port_format_version, Evidence.domains.boundary_world_port.format_version.?);
    try std.testing.expectEqual(Program.boundary_world_port_fingerprint_version, Evidence.domains.boundary_world_port.fingerprint_version);
    try std.testing.expectEqual(Program.boundary_elaboration_policy_fingerprint_version, Evidence.domains.boundary_elaboration_policy.fingerprint_version);
    try std.testing.expectEqual(Program.boundary_elaboration_certificate_format_version, Evidence.domains.boundary_elaboration_certificate.format_version.?);
    try std.testing.expectEqual(Program.boundary_elaboration_certificate_fingerprint_version, Evidence.domains.boundary_elaboration_certificate.fingerprint_version);
    try std.testing.expectEqual(Program.boundary_elaboration_source_map_fingerprint_version, Evidence.domains.boundary_elaboration_source_map.fingerprint_version);
    try std.testing.expectEqual(Program.boundary_elaboration_effect_row_fingerprint_version, Evidence.domains.boundary_elaboration_effect_row.fingerprint_version);
    try std.testing.expectEqual(Program.boundary_elaboration_trace_map_fingerprint_version, Evidence.domains.boundary_elaboration_trace_map.fingerprint_version);
    try std.testing.expectEqual(Program.boundary_normal_form_fingerprint_version, Evidence.domains.boundary_normal_form.fingerprint_version);
    try std.testing.expectEqual(Program.boundary_world_surface_format_version, Evidence.domains.boundary_world_surface.format_version.?);
    try std.testing.expectEqual(Program.boundary_world_surface_fingerprint_version, Evidence.domains.boundary_world_surface.fingerprint_version);
    try std.testing.expectEqual(Program.boundary_world_port_table_fingerprint_version, Evidence.domains.boundary_world_port_table.fingerprint_version);
    try std.testing.expectEqual(Program.boundary_world_value_table_fingerprint_version, Evidence.domains.boundary_world_value_table.fingerprint_version);
    try std.testing.expectEqual(Program.boundary_world_dispatch_table_fingerprint_version, Evidence.domains.boundary_world_dispatch_table.fingerprint_version);
    try std.testing.expectEqual(Program.boundary_world_surface_profile_fingerprint_version, Evidence.domains.boundary_world_surface_profile.fingerprint_version);
    try std.testing.expectEqual(Program.boundary_world_replay_key_recipe_fingerprint_version, Evidence.domains.boundary_world_replay_key_recipe.fingerprint_version);
    try std.testing.expectEqual(Program.boundary_target_policy_fingerprint_version, Evidence.domains.boundary_target_policy.fingerprint_version);
    try std.testing.expectEqual(Program.boundary_target_certificate_format_version, Evidence.domains.boundary_target_certificate.format_version.?);
    try std.testing.expectEqual(Program.boundary_target_certificate_fingerprint_version, Evidence.domains.boundary_target_certificate.fingerprint_version);
    try std.testing.expectEqual(Program.boundary_target_evidence_map_fingerprint_version, Evidence.domains.boundary_target_evidence_map.fingerprint_version);
    try std.testing.expectEqual(Program.boundary_normalization_redex_fingerprint_version, Evidence.domains.boundary_normalization_redex.fingerprint_version);
    try std.testing.expectEqual(Program.boundary_normalization_rule_fingerprint_version, Evidence.domains.boundary_normalization_rule.fingerprint_version);
    try std.testing.expectEqual(Program.boundary_normalization_step_fingerprint_version, Evidence.domains.boundary_normalization_step.fingerprint_version);
    try std.testing.expectEqual(Program.boundary_normalization_trace_fingerprint_version, Evidence.domains.boundary_normalization_trace.fingerprint_version);
    try std.testing.expectEqual(Program.boundary_normalization_certificate_format_version, Evidence.domains.boundary_normalization_certificate.format_version.?);
    try std.testing.expectEqual(Program.boundary_normalization_certificate_fingerprint_version, Evidence.domains.boundary_normalization_certificate.fingerprint_version);
    try std.testing.expectEqual(Program.boundary_route_lowering_fingerprint_version, Evidence.domains.boundary_route_lowering.fingerprint_version);
    try std.testing.expectEqual(Program.boundary_plan_builder_fingerprint_version, Evidence.domains.boundary_plan_builder.fingerprint_version);
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

test "boundary normalization redex rule step trace and certificate fingerprints are stable" {
    const source_ref = Evidence.refFor(Evidence.domains.program_plan, Program.compiled_plan.hash(), .{ .label = Program.contract.label });
    const residual_ref = Evidence.refFor(Evidence.domains.program_plan, Program.compiled_plan.hash(), .{ .label = "residual" });
    const closure_certificate_ref = Evidence.refFor(Evidence.domains.boundary_closure_certificate, 0xC10C, .{ .label = "closure" });
    const provider_program_ref = Evidence.refFor(Evidence.domains.program_plan, 0xC10D, .{ .label = "normalization.provider" });
    const provider_ref = Evidence.refFor(Evidence.domains.provider_manifest, 0xC10E, .{ .label = "normalization.provider_manifest" });
    const offer_ref = Evidence.refFor(Evidence.domains.provider_offer, 0xC10F, .{ .label = "normalization.provider_offer" });
    const capability_ref = Evidence.refFor(Evidence.domains.capability, 0xC110, .{ .label = "normalization.capability" });
    const resume_ref = Evidence.BoundaryValueRef.init("i32", null);
    const shape = Evidence.BoundaryEffectShape.init(.{
        .program_label = "normalization-source",
        .kind = .operation,
        .site_index = 0,
        .site_fingerprint = 0xB011_DA7A,
        .protocol_label = "approval",
        .protocol_op_fingerprint = 0xB011_DA7A,
        .expected_resume_ref = resume_ref,
    });
    const static_plan = Evidence.BoundaryStaticTreatyPlan.init(.{
        .label = "normalization.provider_plan",
        .source_shape = shape,
        .selected_provider_offer_ref = offer_ref,
        .selected_provider_ref = provider_ref,
        .selected_capability_ref = capability_ref,
        .selected_semantic_body = .boundary_program,
        .selected_provider_program_ref = provider_program_ref,
        .selected_provider_program_mapping_fingerprint = 0xC111,
        .selected_provider_program_request_mapping_tag = "payload_to_args",
        .selected_provider_program_result_mapping_tag = "result_to_resume",
        .selected_provider_program_effect_shape_count = 1,
        .selected_provider_program_effect_shape_fingerprint = shape.fingerprint,
    });
    const static_plans = [_]Evidence.BoundaryStaticTreatyPlan{static_plan};
    const redex_dependencies = [_]Evidence.Dependency{
        .{ .role = .source, .ref = shape.evidenceRef() },
        .{ .role = .residual_program, .ref = Evidence.refFor(Evidence.domains.program_plan, residual_ref.fingerprint, .{}) },
    };
    const redex = Evidence.BoundaryNormalizationRedex.init(.{
        .label = "approval.request",
        .source_effect_shape_ref = shape.evidenceRef(),
        .coordinates = .{ .function_index = 0, .block_index = 0, .instruction_index = 0, .site_index = 0 },
        .kind = .operation_site,
        .selected_static_treaty_plan_ref = static_plan.evidenceRef(),
        .current_program_plan_ref = source_ref,
        .semantic_body = .boundary_program,
        .expected_lowering_kind = .provider_program_call,
        .evidence_dependencies = redex_dependencies[0..],
    });
    const same_redex = Evidence.BoundaryNormalizationRedex.init(.{
        .label = "approval.request",
        .source_effect_shape_ref = shape.evidenceRef(),
        .coordinates = .{ .function_index = 0, .block_index = 0, .instruction_index = 0, .site_index = 0 },
        .kind = .operation_site,
        .selected_static_treaty_plan_ref = static_plan.evidenceRef(),
        .current_program_plan_ref = source_ref,
        .semantic_body = .boundary_program,
        .expected_lowering_kind = .provider_program_call,
        .evidence_dependencies = redex_dependencies[0..],
    });
    const distinct_site_redex = Evidence.BoundaryNormalizationRedex.init(.{
        .label = "approval.distinct-site",
        .source_effect_shape_ref = shape.evidenceRef(),
        .coordinates = .{ .function_index = 0, .block_index = 0, .instruction_index = 2, .site_index = 7 },
        .kind = .operation_site,
        .selected_static_treaty_plan_ref = static_plan.evidenceRef(),
        .current_program_plan_ref = source_ref,
        .semantic_body = .boundary_program,
        .expected_lowering_kind = .provider_program_call,
        .evidence_dependencies = redex_dependencies[0..],
    });
    const rule_dependencies = [_]Evidence.Dependency{.{ .role = .source, .ref = shape.evidenceRef() }};
    const rule = Evidence.BoundaryNormalizationRewriteRule.init(.{
        .label = "approval.request",
        .kind = .provider_program_call,
        .evidence_dependencies = rule_dependencies[0..],
        .produced_source_map_entries = 1,
        .produced_trace_map_entries = 1,
        .produced_effect_row_entries = 1,
    });
    const source_map_entry = Evidence.BoundaryElaborationSourceMap.Entry{
        .source_ref = shape.evidenceRef(),
        .residual_ref = residual_ref,
        .source_site_index = 0,
        .residual_site_index = 0,
        .provider_program_ref = provider_program_ref,
        .static_treaty_plan_ref = static_plan.evidenceRef(),
        .disposition = .provider_program_linked,
        .label = "approval.request",
    };
    const route_lowering_fingerprint = Evidence.boundaryNormalizationRouteLoweringFingerprint(source_map_entry, residual_ref.fingerprint);
    const step = Evidence.BoundaryNormalizationRewriteStep.init(.{
        .step_index = 0,
        .redex_ref = redex.evidenceRef(),
        .rewrite_rule_ref = rule.evidenceRef(),
        .selected_static_treaty_plan_ref = static_plan.evidenceRef(),
        .source_effect_shape_ref = shape.evidenceRef(),
        .input_program_plan_hash = source_ref.fingerprint,
        .output_program_plan_hash = residual_ref.fingerprint,
        .builder_state_fingerprint = route_lowering_fingerprint,
        .provider_program_ref = provider_program_ref,
        .provider_offer_ref = offer_ref,
        .summary = "provider_program_call",
    });
    const redexes = [_]Evidence.BoundaryNormalizationRedex{redex};
    const rules = [_]Evidence.BoundaryNormalizationRewriteRule{rule};
    const steps = [_]Evidence.BoundaryNormalizationRewriteStep{step};
    const source_map_entries = [_]Evidence.BoundaryElaborationSourceMap.Entry{source_map_entry};
    const source_map = Evidence.BoundaryElaborationSourceMap.init("normalization.source_map", source_map_entries[0..], &.{});
    const effect_row = Evidence.BoundaryElaborationEffectRow.init(.{
        .label = "normalization.effect_row",
        .source_program_ref = source_ref,
        .residual_program_ref = residual_ref,
        .normal_form = .strict_closed,
        .source_effect_shapes = 1,
        .closed_effect_shapes = 1,
        .provider_program_links = 1,
    });
    const trace_map_entries = [_]Evidence.BoundaryElaborationTraceMap.Entry{.{
        .source_ref = shape.evidenceRef(),
        .residual_ref = residual_ref,
        .trace_label = "approval.request",
    }};
    const trace_map = Evidence.BoundaryElaborationTraceMap.init("normalization.trace_map", trace_map_entries[0..]);
    const normal_form = Evidence.BoundaryNormalForm.init("normalization.normal_form", .strict_closed, closure_certificate_ref, effect_row.evidenceRef(), 0);
    const eliminated = [_]Evidence.Ref{redex.evidenceRef()};
    const trace_deps = [_]Evidence.Dependency{
        .{ .role = .closure_certificate, .ref = closure_certificate_ref },
        .{ .role = .residual_program, .ref = residual_ref },
        .{ .role = .elaboration_source_map, .ref = source_map.evidenceRef() },
        .{ .role = .elaboration_effect_row, .ref = effect_row.evidenceRef() },
        .{ .role = .normal_form, .ref = normal_form.evidenceRef() },
    };
    const trace = Evidence.BoundaryNormalizationTrace.init(.{
        .label = "normalization.trace",
        .root_program_ref = source_ref,
        .closure_certificate_ref = closure_certificate_ref,
        .rewrite_steps = steps[0..],
        .eliminated_redex_refs = eliminated[0..],
        .final_program_plan_hash = residual_ref.fingerprint,
        .final_normal_form = .strict_closed,
        .evidence_dependencies = trace_deps[0..],
    });
    const world_surface = Evidence.BoundaryWorldSurface.init(.{
        .label = "normalization.world_surface",
        .residual_program_label = "residual",
        .residual_program_ref = residual_ref,
        .elaboration_certificate_ref = Evidence.refFor(Evidence.domains.boundary_elaboration_certificate, 0xE1AB, .{ .label = "elaboration" }),
        .source_map_ref = source_map.evidenceRef(),
        .effect_row_ref = effect_row.evidenceRef(),
        .port_table_ref = Evidence.refFor(Evidence.domains.boundary_world_port_table, 0x7100, .{}),
        .value_table_ref = Evidence.refFor(Evidence.domains.boundary_world_value_table, 0x7101, .{}),
        .dispatch_table_ref = Evidence.refFor(Evidence.domains.boundary_world_dispatch_table, 0x7102, .{}),
        .profile_ref = Evidence.refFor(Evidence.domains.boundary_world_surface_profile, 0x7103, .{}),
        .replay_key_recipe_ref = Evidence.refFor(Evidence.domains.boundary_world_replay_key_recipe, 0x7104, .{}),
        .normal_form = .strict_closed,
        .world_port_count = 0,
    });
    const evidence_map = Evidence.BoundaryTargetEvidenceMap.init("normalization.evidence_map", &.{});
    const normalization_dependencies = [_]Evidence.Dependency{
        .{ .role = .normalization_trace, .ref = trace.evidenceRef() },
        .{ .role = .elaboration_source_map, .ref = source_map.evidenceRef() },
        .{ .role = .elaboration_trace_map, .ref = trace_map.evidenceRef() },
        .{ .role = .target_evidence_map, .ref = evidence_map.evidenceRef() },
        .{ .role = .elaboration_effect_row, .ref = effect_row.evidenceRef() },
        .{ .role = .normal_form, .ref = normal_form.evidenceRef() },
        .{ .role = .world_surface, .ref = world_surface.evidenceRef() },
    };
    const certificate = Evidence.BoundaryNormalizationCertificate.init(.{
        .label = "normalization.certificate",
        .closure_certificate_ref = closure_certificate_ref,
        .target_policy_fingerprint = Evidence.BoundaryTargetPolicy.strictClosed().fingerprint(),
        .normalization_trace_ref = trace.evidenceRef(),
        .final_program_plan_hash = residual_ref.fingerprint,
        .source_map_ref = source_map.evidenceRef(),
        .trace_map_ref = trace_map.evidenceRef(),
        .evidence_map_ref = evidence_map.evidenceRef(),
        .effect_row_ref = effect_row.evidenceRef(),
        .normal_form_ref = normal_form.evidenceRef(),
        .world_surface_ref = world_surface.evidenceRef(),
        .dependencies = normalization_dependencies[0..],
    });

    try std.testing.expectEqual(redex.fingerprint, same_redex.fingerprint);
    try std.testing.expectEqual(@as(?usize, 7), distinct_site_redex.evidenceRef().site_index);
    try std.testing.expectEqual(Evidence.domains.boundary_normalization_redex.id, redex.evidenceRef().domain_id);
    try std.testing.expectEqual(Evidence.domains.boundary_normalization_rule.id, rule.evidenceRef().domain_id);
    try std.testing.expectEqual(Evidence.domains.boundary_normalization_step.id, step.evidenceRef().domain_id);
    try std.testing.expectEqual(Evidence.domains.boundary_normalization_trace.id, trace.evidenceRef().domain_id);
    try std.testing.expectEqual(Evidence.domains.boundary_normalization_certificate.id, certificate.evidenceView().domain);
    try certificate.check(Evidence.BoundaryTargetPolicy.strictClosed(), trace, redexes[0..], rules[0..], static_plans[0..], source_map, trace_map, evidence_map, effect_row, normal_form, world_surface);

    const morphism_ref = Evidence.refFor(Evidence.domains.morphism_offer, 0xC112, .{ .label = "normalization.morphism" });
    const residualized_plan_dependencies = [_]Evidence.Dependency{
        .{ .role = .morphism, .ref = morphism_ref },
        .{ .role = .residual_program, .ref = residual_ref },
    };
    const residualized_plan = Evidence.BoundaryStaticTreatyPlan.init(.{
        .label = "normalization.residualized_plan",
        .source_shape = shape,
        .selected_semantic_body = .residualized_program,
        .selected_morphism_ref = morphism_ref,
        .selected_morphism_semantic_body = .residualized_program,
        .dependencies = residualized_plan_dependencies[0..],
    });
    const residualized_source_map_entry = Evidence.BoundaryElaborationSourceMap.Entry{
        .source_ref = shape.evidenceRef(),
        .residual_ref = residual_ref,
        .source_site_index = 0,
        .residual_site_index = 0,
        .static_treaty_plan_ref = residualized_plan.evidenceRef(),
        .disposition = .residualized,
        .label = "approval.residualized",
    };
    const residualized_route_lowering_fingerprint = Evidence.boundaryNormalizationRouteLoweringFingerprint(residualized_source_map_entry, residual_ref.fingerprint);
    const residualized_redex = Evidence.BoundaryNormalizationRedex.init(.{
        .label = "approval.residualized",
        .source_effect_shape_ref = shape.evidenceRef(),
        .coordinates = .{ .function_index = 0, .block_index = 0, .instruction_index = 0, .site_index = 0 },
        .kind = .operation_site,
        .selected_static_treaty_plan_ref = residualized_plan.evidenceRef(),
        .current_program_plan_ref = source_ref,
        .semantic_body = .residualized_program,
        .expected_lowering_kind = .residualized_morphism,
        .evidence_dependencies = redex_dependencies[0..],
    });
    const residualized_rule = Evidence.BoundaryNormalizationRewriteRule.init(.{
        .label = "approval.residualized",
        .kind = .residualized_morphism,
        .evidence_dependencies = rule_dependencies[0..],
        .produced_source_map_entries = 1,
        .produced_trace_map_entries = 1,
        .produced_effect_row_entries = 1,
    });
    const residualized_step = Evidence.BoundaryNormalizationRewriteStep.init(.{
        .step_index = 0,
        .redex_ref = residualized_redex.evidenceRef(),
        .rewrite_rule_ref = residualized_rule.evidenceRef(),
        .selected_static_treaty_plan_ref = residualized_plan.evidenceRef(),
        .source_effect_shape_ref = shape.evidenceRef(),
        .input_program_plan_hash = source_ref.fingerprint,
        .output_program_plan_hash = residual_ref.fingerprint,
        .builder_state_fingerprint = residualized_route_lowering_fingerprint,
        .morphism_or_pipeline_ref = morphism_ref,
        .summary = "residualized_morphism",
    });
    const residualized_redexes = [_]Evidence.BoundaryNormalizationRedex{residualized_redex};
    const residualized_rules = [_]Evidence.BoundaryNormalizationRewriteRule{residualized_rule};
    const residualized_steps = [_]Evidence.BoundaryNormalizationRewriteStep{residualized_step};
    const residualized_static_plans = [_]Evidence.BoundaryStaticTreatyPlan{residualized_plan};
    const residualized_source_map_entries = [_]Evidence.BoundaryElaborationSourceMap.Entry{residualized_source_map_entry};
    const residualized_source_map = Evidence.BoundaryElaborationSourceMap.init("normalization.residualized.source_map", residualized_source_map_entries[0..], &.{});
    const residualized_trace_map_entries = [_]Evidence.BoundaryElaborationTraceMap.Entry{.{
        .source_ref = shape.evidenceRef(),
        .residual_ref = residual_ref,
        .trace_label = "approval.residualized",
    }};
    const residualized_trace_map = Evidence.BoundaryElaborationTraceMap.init("normalization.residualized.trace_map", residualized_trace_map_entries[0..]);
    const residualized_effect_row = Evidence.BoundaryElaborationEffectRow.init(.{
        .label = "normalization.residualized.effect_row",
        .source_program_ref = source_ref,
        .residual_program_ref = residual_ref,
        .normal_form = .strict_closed,
        .source_effect_shapes = 1,
        .closed_effect_shapes = 1,
        .residualized_routes = 1,
    });
    const residualized_normal_form = Evidence.BoundaryNormalForm.init("normalization.residualized.normal_form", .strict_closed, closure_certificate_ref, residualized_effect_row.evidenceRef(), 0);
    const residualized_eliminated = [_]Evidence.Ref{residualized_redex.evidenceRef()};
    const residualized_trace_deps = [_]Evidence.Dependency{
        .{ .role = .closure_certificate, .ref = closure_certificate_ref },
        .{ .role = .residual_program, .ref = residual_ref },
        .{ .role = .elaboration_source_map, .ref = residualized_source_map.evidenceRef() },
        .{ .role = .elaboration_effect_row, .ref = residualized_effect_row.evidenceRef() },
        .{ .role = .normal_form, .ref = residualized_normal_form.evidenceRef() },
    };
    const residualized_trace = Evidence.BoundaryNormalizationTrace.init(.{
        .label = "normalization.residualized.trace",
        .root_program_ref = source_ref,
        .closure_certificate_ref = closure_certificate_ref,
        .rewrite_steps = residualized_steps[0..],
        .eliminated_redex_refs = residualized_eliminated[0..],
        .final_program_plan_hash = residual_ref.fingerprint,
        .final_normal_form = .strict_closed,
        .evidence_dependencies = residualized_trace_deps[0..],
    });
    const residualized_world_surface = Evidence.BoundaryWorldSurface.init(.{
        .label = "normalization.residualized.world_surface",
        .residual_program_label = "residual",
        .residual_program_ref = residual_ref,
        .elaboration_certificate_ref = Evidence.refFor(Evidence.domains.boundary_elaboration_certificate, 0xE1AB, .{ .label = "elaboration" }),
        .source_map_ref = residualized_source_map.evidenceRef(),
        .effect_row_ref = residualized_effect_row.evidenceRef(),
        .port_table_ref = Evidence.refFor(Evidence.domains.boundary_world_port_table, 0x7100, .{}),
        .value_table_ref = Evidence.refFor(Evidence.domains.boundary_world_value_table, 0x7101, .{}),
        .dispatch_table_ref = Evidence.refFor(Evidence.domains.boundary_world_dispatch_table, 0x7102, .{}),
        .profile_ref = Evidence.refFor(Evidence.domains.boundary_world_surface_profile, 0x7103, .{}),
        .replay_key_recipe_ref = Evidence.refFor(Evidence.domains.boundary_world_replay_key_recipe, 0x7104, .{}),
        .normal_form = .strict_closed,
        .world_port_count = 0,
    });
    const residualized_certificate = Evidence.BoundaryNormalizationCertificate.init(.{
        .label = "normalization.residualized.certificate",
        .closure_certificate_ref = closure_certificate_ref,
        .target_policy_fingerprint = Evidence.BoundaryTargetPolicy.strictClosed().fingerprint(),
        .normalization_trace_ref = residualized_trace.evidenceRef(),
        .final_program_plan_hash = residual_ref.fingerprint,
        .source_map_ref = residualized_source_map.evidenceRef(),
        .trace_map_ref = residualized_trace_map.evidenceRef(),
        .evidence_map_ref = evidence_map.evidenceRef(),
        .effect_row_ref = residualized_effect_row.evidenceRef(),
        .normal_form_ref = residualized_normal_form.evidenceRef(),
        .world_surface_ref = residualized_world_surface.evidenceRef(),
        .dependencies = (&[_]Evidence.Dependency{
            .{ .role = .normalization_trace, .ref = residualized_trace.evidenceRef() },
            .{ .role = .elaboration_source_map, .ref = residualized_source_map.evidenceRef() },
            .{ .role = .elaboration_trace_map, .ref = residualized_trace_map.evidenceRef() },
            .{ .role = .target_evidence_map, .ref = evidence_map.evidenceRef() },
            .{ .role = .elaboration_effect_row, .ref = residualized_effect_row.evidenceRef() },
            .{ .role = .normal_form, .ref = residualized_normal_form.evidenceRef() },
            .{ .role = .world_surface, .ref = residualized_world_surface.evidenceRef() },
        })[0..],
    });
    try residualized_certificate.check(Evidence.BoundaryTargetPolicy.strictClosed(), residualized_trace, residualized_redexes[0..], residualized_rules[0..], residualized_static_plans[0..], residualized_source_map, residualized_trace_map, evidence_map, residualized_effect_row, residualized_normal_form, residualized_world_surface);

    const unbound_residualized_plan = Evidence.BoundaryStaticTreatyPlan.init(.{
        .label = "normalization.unbound_residualized_plan",
        .source_shape = shape,
        .selected_semantic_body = .residualized_program,
        .selected_morphism_ref = morphism_ref,
        .selected_morphism_semantic_body = .residualized_program,
        .dependencies = (&[_]Evidence.Dependency{.{ .role = .morphism, .ref = morphism_ref }})[0..],
    });
    var unbound_residualized_entry = residualized_source_map_entry;
    unbound_residualized_entry.static_treaty_plan_ref = unbound_residualized_plan.evidenceRef();
    const unbound_residualized_source_map_entries = [_]Evidence.BoundaryElaborationSourceMap.Entry{unbound_residualized_entry};
    const unbound_residualized_source_map = Evidence.BoundaryElaborationSourceMap.init("normalization.unbound_residualized.source_map", unbound_residualized_source_map_entries[0..], &.{});
    const unbound_residualized_route_lowering_fingerprint = Evidence.boundaryNormalizationRouteLoweringFingerprint(unbound_residualized_entry, residual_ref.fingerprint);
    var unbound_residualized_redex = residualized_redex;
    unbound_residualized_redex.selected_static_treaty_plan_ref = unbound_residualized_plan.evidenceRef();
    unbound_residualized_redex.fingerprint = unbound_residualized_redex.computeFingerprint();
    var unbound_residualized_step = residualized_step;
    unbound_residualized_step.redex_ref = unbound_residualized_redex.evidenceRef();
    unbound_residualized_step.selected_static_treaty_plan_ref = unbound_residualized_plan.evidenceRef();
    unbound_residualized_step.builder_state_fingerprint = unbound_residualized_route_lowering_fingerprint;
    unbound_residualized_step.fingerprint = unbound_residualized_step.computeFingerprint();
    const unbound_residualized_redexes = [_]Evidence.BoundaryNormalizationRedex{unbound_residualized_redex};
    const unbound_residualized_steps = [_]Evidence.BoundaryNormalizationRewriteStep{unbound_residualized_step};
    const unbound_residualized_static_plans = [_]Evidence.BoundaryStaticTreatyPlan{unbound_residualized_plan};
    const unbound_residualized_trace_deps = [_]Evidence.Dependency{
        .{ .role = .closure_certificate, .ref = closure_certificate_ref },
        .{ .role = .residual_program, .ref = residual_ref },
        .{ .role = .elaboration_source_map, .ref = unbound_residualized_source_map.evidenceRef() },
        .{ .role = .elaboration_effect_row, .ref = residualized_effect_row.evidenceRef() },
        .{ .role = .normal_form, .ref = residualized_normal_form.evidenceRef() },
    };
    const unbound_residualized_trace = Evidence.BoundaryNormalizationTrace.init(.{
        .label = "normalization.unbound_residualized.trace",
        .root_program_ref = source_ref,
        .closure_certificate_ref = closure_certificate_ref,
        .rewrite_steps = unbound_residualized_steps[0..],
        .eliminated_redex_refs = (&[_]Evidence.Ref{unbound_residualized_redex.evidenceRef()})[0..],
        .final_program_plan_hash = residual_ref.fingerprint,
        .final_normal_form = .strict_closed,
        .evidence_dependencies = unbound_residualized_trace_deps[0..],
    });
    const unbound_residualized_world_surface = Evidence.BoundaryWorldSurface.init(.{
        .label = "normalization.unbound_residualized.world_surface",
        .residual_program_label = "residual",
        .residual_program_ref = residual_ref,
        .elaboration_certificate_ref = Evidence.refFor(Evidence.domains.boundary_elaboration_certificate, 0xE1AB, .{ .label = "elaboration" }),
        .source_map_ref = unbound_residualized_source_map.evidenceRef(),
        .effect_row_ref = residualized_effect_row.evidenceRef(),
        .port_table_ref = Evidence.refFor(Evidence.domains.boundary_world_port_table, 0x7100, .{}),
        .value_table_ref = Evidence.refFor(Evidence.domains.boundary_world_value_table, 0x7101, .{}),
        .dispatch_table_ref = Evidence.refFor(Evidence.domains.boundary_world_dispatch_table, 0x7102, .{}),
        .profile_ref = Evidence.refFor(Evidence.domains.boundary_world_surface_profile, 0x7103, .{}),
        .replay_key_recipe_ref = Evidence.refFor(Evidence.domains.boundary_world_replay_key_recipe, 0x7104, .{}),
        .normal_form = .strict_closed,
        .world_port_count = 0,
    });
    const unbound_residualized_certificate = Evidence.BoundaryNormalizationCertificate.init(.{
        .label = "normalization.unbound_residualized.certificate",
        .closure_certificate_ref = closure_certificate_ref,
        .target_policy_fingerprint = Evidence.BoundaryTargetPolicy.strictClosed().fingerprint(),
        .normalization_trace_ref = unbound_residualized_trace.evidenceRef(),
        .final_program_plan_hash = residual_ref.fingerprint,
        .source_map_ref = unbound_residualized_source_map.evidenceRef(),
        .trace_map_ref = residualized_trace_map.evidenceRef(),
        .evidence_map_ref = evidence_map.evidenceRef(),
        .effect_row_ref = residualized_effect_row.evidenceRef(),
        .normal_form_ref = residualized_normal_form.evidenceRef(),
        .world_surface_ref = unbound_residualized_world_surface.evidenceRef(),
        .dependencies = (&[_]Evidence.Dependency{
            .{ .role = .normalization_trace, .ref = unbound_residualized_trace.evidenceRef() },
            .{ .role = .elaboration_source_map, .ref = unbound_residualized_source_map.evidenceRef() },
            .{ .role = .elaboration_trace_map, .ref = residualized_trace_map.evidenceRef() },
            .{ .role = .target_evidence_map, .ref = evidence_map.evidenceRef() },
            .{ .role = .elaboration_effect_row, .ref = residualized_effect_row.evidenceRef() },
            .{ .role = .normal_form, .ref = residualized_normal_form.evidenceRef() },
            .{ .role = .world_surface, .ref = unbound_residualized_world_surface.evidenceRef() },
        })[0..],
    });
    try std.testing.expectEqual(
        error.BoundaryNormalizationCertificateMismatch,
        unbound_residualized_certificate.check(Evidence.BoundaryTargetPolicy.strictClosed(), unbound_residualized_trace, unbound_residualized_redexes[0..], residualized_rules[0..], unbound_residualized_static_plans[0..], unbound_residualized_source_map, residualized_trace_map, evidence_map, residualized_effect_row, residualized_normal_form, unbound_residualized_world_surface),
    );

    const missing_resume_shape = Evidence.BoundaryEffectShape.init(.{
        .program_label = "normalization-source",
        .kind = .operation,
        .site_index = 0,
        .site_fingerprint = 0xB011_DA7A,
        .protocol_label = "approval",
        .protocol_op_fingerprint = 0xB011_DA7A,
    });
    const missing_resume_static_plan = Evidence.BoundaryStaticTreatyPlan.init(.{
        .label = "normalization.provider_plan.missing_resume",
        .source_shape = missing_resume_shape,
        .selected_provider_offer_ref = offer_ref,
        .selected_provider_ref = provider_ref,
        .selected_capability_ref = capability_ref,
        .selected_semantic_body = .boundary_program,
        .selected_provider_program_ref = provider_program_ref,
        .selected_provider_program_mapping_fingerprint = 0xC111,
        .selected_provider_program_request_mapping_tag = "payload_to_args",
        .selected_provider_program_result_mapping_tag = "result_to_resume",
        .selected_provider_program_effect_shape_count = 1,
        .selected_provider_program_effect_shape_fingerprint = missing_resume_shape.fingerprint,
    });
    const missing_resume_redex_dependencies = [_]Evidence.Dependency{
        .{ .role = .source, .ref = missing_resume_shape.evidenceRef() },
        .{ .role = .residual_program, .ref = Evidence.refFor(Evidence.domains.program_plan, residual_ref.fingerprint, .{}) },
    };
    const missing_resume_redex = Evidence.BoundaryNormalizationRedex.init(.{
        .label = "approval.request",
        .source_effect_shape_ref = missing_resume_shape.evidenceRef(),
        .coordinates = .{ .function_index = 0, .block_index = 0, .instruction_index = 0, .site_index = 0 },
        .kind = .operation_site,
        .selected_static_treaty_plan_ref = missing_resume_static_plan.evidenceRef(),
        .current_program_plan_ref = source_ref,
        .semantic_body = .boundary_program,
        .expected_lowering_kind = .provider_program_call,
        .evidence_dependencies = missing_resume_redex_dependencies[0..],
    });
    const missing_resume_rule_dependencies = [_]Evidence.Dependency{.{ .role = .source, .ref = missing_resume_shape.evidenceRef() }};
    const missing_resume_rule = Evidence.BoundaryNormalizationRewriteRule.init(.{
        .label = "approval.request",
        .kind = .provider_program_call,
        .evidence_dependencies = missing_resume_rule_dependencies[0..],
        .produced_source_map_entries = 1,
        .produced_trace_map_entries = 1,
        .produced_effect_row_entries = 1,
    });
    const missing_resume_source_map_entry = Evidence.BoundaryElaborationSourceMap.Entry{
        .source_ref = missing_resume_shape.evidenceRef(),
        .residual_ref = residual_ref,
        .source_site_index = 0,
        .residual_site_index = 0,
        .provider_program_ref = provider_program_ref,
        .static_treaty_plan_ref = missing_resume_static_plan.evidenceRef(),
        .disposition = .provider_program_linked,
        .label = "approval.request",
    };
    const missing_resume_step = Evidence.BoundaryNormalizationRewriteStep.init(.{
        .step_index = 0,
        .redex_ref = missing_resume_redex.evidenceRef(),
        .rewrite_rule_ref = missing_resume_rule.evidenceRef(),
        .selected_static_treaty_plan_ref = missing_resume_static_plan.evidenceRef(),
        .source_effect_shape_ref = missing_resume_shape.evidenceRef(),
        .input_program_plan_hash = source_ref.fingerprint,
        .output_program_plan_hash = residual_ref.fingerprint,
        .builder_state_fingerprint = Evidence.boundaryNormalizationRouteLoweringFingerprint(missing_resume_source_map_entry, residual_ref.fingerprint),
        .provider_program_ref = provider_program_ref,
        .provider_offer_ref = offer_ref,
        .summary = "provider_program_call",
    });
    const missing_resume_redexes = [_]Evidence.BoundaryNormalizationRedex{missing_resume_redex};
    const missing_resume_rules = [_]Evidence.BoundaryNormalizationRewriteRule{missing_resume_rule};
    const missing_resume_steps = [_]Evidence.BoundaryNormalizationRewriteStep{missing_resume_step};
    const missing_resume_static_plans = [_]Evidence.BoundaryStaticTreatyPlan{missing_resume_static_plan};
    const missing_resume_source_map_entries = [_]Evidence.BoundaryElaborationSourceMap.Entry{missing_resume_source_map_entry};
    const missing_resume_source_map = Evidence.BoundaryElaborationSourceMap.init("normalization.missing_resume.source_map", missing_resume_source_map_entries[0..], &.{});
    const missing_resume_trace_map_entries = [_]Evidence.BoundaryElaborationTraceMap.Entry{.{
        .source_ref = missing_resume_shape.evidenceRef(),
        .residual_ref = residual_ref,
        .trace_label = "approval.request",
    }};
    const missing_resume_trace_map = Evidence.BoundaryElaborationTraceMap.init("normalization.missing_resume.trace_map", missing_resume_trace_map_entries[0..]);
    const missing_resume_eliminated = [_]Evidence.Ref{missing_resume_redex.evidenceRef()};
    const missing_resume_trace_deps = [_]Evidence.Dependency{
        .{ .role = .closure_certificate, .ref = closure_certificate_ref },
        .{ .role = .residual_program, .ref = residual_ref },
        .{ .role = .elaboration_source_map, .ref = missing_resume_source_map.evidenceRef() },
        .{ .role = .elaboration_effect_row, .ref = effect_row.evidenceRef() },
        .{ .role = .normal_form, .ref = normal_form.evidenceRef() },
    };
    const missing_resume_trace = Evidence.BoundaryNormalizationTrace.init(.{
        .label = "normalization.missing_resume.trace",
        .root_program_ref = source_ref,
        .closure_certificate_ref = closure_certificate_ref,
        .rewrite_steps = missing_resume_steps[0..],
        .eliminated_redex_refs = missing_resume_eliminated[0..],
        .final_program_plan_hash = residual_ref.fingerprint,
        .final_normal_form = .strict_closed,
        .evidence_dependencies = missing_resume_trace_deps[0..],
    });
    const missing_resume_world_surface = Evidence.BoundaryWorldSurface.init(.{
        .label = "normalization.missing_resume.world_surface",
        .residual_program_label = "residual",
        .residual_program_ref = residual_ref,
        .elaboration_certificate_ref = Evidence.refFor(Evidence.domains.boundary_elaboration_certificate, 0xE1AB, .{ .label = "elaboration" }),
        .source_map_ref = missing_resume_source_map.evidenceRef(),
        .effect_row_ref = effect_row.evidenceRef(),
        .port_table_ref = Evidence.refFor(Evidence.domains.boundary_world_port_table, 0x7100, .{}),
        .value_table_ref = Evidence.refFor(Evidence.domains.boundary_world_value_table, 0x7101, .{}),
        .dispatch_table_ref = Evidence.refFor(Evidence.domains.boundary_world_dispatch_table, 0x7102, .{}),
        .profile_ref = Evidence.refFor(Evidence.domains.boundary_world_surface_profile, 0x7103, .{}),
        .replay_key_recipe_ref = Evidence.refFor(Evidence.domains.boundary_world_replay_key_recipe, 0x7104, .{}),
        .normal_form = .strict_closed,
        .world_port_count = 0,
    });
    const missing_resume_certificate = Evidence.BoundaryNormalizationCertificate.init(.{
        .label = "normalization.missing_resume.certificate",
        .closure_certificate_ref = closure_certificate_ref,
        .target_policy_fingerprint = Evidence.BoundaryTargetPolicy.strictClosed().fingerprint(),
        .normalization_trace_ref = missing_resume_trace.evidenceRef(),
        .final_program_plan_hash = residual_ref.fingerprint,
        .source_map_ref = missing_resume_source_map.evidenceRef(),
        .trace_map_ref = missing_resume_trace_map.evidenceRef(),
        .evidence_map_ref = evidence_map.evidenceRef(),
        .effect_row_ref = effect_row.evidenceRef(),
        .normal_form_ref = normal_form.evidenceRef(),
        .world_surface_ref = missing_resume_world_surface.evidenceRef(),
        .dependencies = (&[_]Evidence.Dependency{
            .{ .role = .normalization_trace, .ref = missing_resume_trace.evidenceRef() },
            .{ .role = .elaboration_source_map, .ref = missing_resume_source_map.evidenceRef() },
            .{ .role = .elaboration_trace_map, .ref = missing_resume_trace_map.evidenceRef() },
            .{ .role = .target_evidence_map, .ref = evidence_map.evidenceRef() },
            .{ .role = .elaboration_effect_row, .ref = effect_row.evidenceRef() },
            .{ .role = .normal_form, .ref = normal_form.evidenceRef() },
            .{ .role = .world_surface, .ref = missing_resume_world_surface.evidenceRef() },
        })[0..],
    });
    try std.testing.expectEqual(
        error.BoundaryNormalizationCertificateMismatch,
        missing_resume_certificate.check(Evidence.BoundaryTargetPolicy.strictClosed(), missing_resume_trace, missing_resume_redexes[0..], missing_resume_rules[0..], missing_resume_static_plans[0..], missing_resume_source_map, missing_resume_trace_map, evidence_map, effect_row, normal_form, missing_resume_world_surface),
    );
    var zero_rewrite_policy = Evidence.BoundaryTargetPolicy.strictClosed();
    zero_rewrite_policy.max_rewrite_steps = 0;
    const capped_certificate = Evidence.BoundaryNormalizationCertificate.init(.{
        .label = "normalization.capped_certificate",
        .closure_certificate_ref = closure_certificate_ref,
        .target_policy_fingerprint = zero_rewrite_policy.fingerprint(),
        .normalization_trace_ref = trace.evidenceRef(),
        .final_program_plan_hash = residual_ref.fingerprint,
        .source_map_ref = source_map.evidenceRef(),
        .trace_map_ref = trace_map.evidenceRef(),
        .evidence_map_ref = evidence_map.evidenceRef(),
        .effect_row_ref = effect_row.evidenceRef(),
        .normal_form_ref = normal_form.evidenceRef(),
        .world_surface_ref = world_surface.evidenceRef(),
        .dependencies = normalization_dependencies[0..],
    });
    try std.testing.expectEqual(
        error.BoundaryNormalizationPolicyMismatch,
        capped_certificate.check(zero_rewrite_policy, trace, redexes[0..], rules[0..], static_plans[0..], source_map, trace_map, evidence_map, effect_row, normal_form, world_surface),
    );
    var provider_rewrite_disabled_policy = Evidence.BoundaryTargetPolicy.strictClosed();
    provider_rewrite_disabled_policy.allow_program_backed_providers = false;
    const provider_rewrite_disabled_certificate = Evidence.BoundaryNormalizationCertificate.init(.{
        .label = "normalization.provider_rewrite_disabled_certificate",
        .closure_certificate_ref = closure_certificate_ref,
        .target_policy_fingerprint = provider_rewrite_disabled_policy.fingerprint(),
        .normalization_trace_ref = trace.evidenceRef(),
        .final_program_plan_hash = residual_ref.fingerprint,
        .source_map_ref = source_map.evidenceRef(),
        .trace_map_ref = trace_map.evidenceRef(),
        .evidence_map_ref = evidence_map.evidenceRef(),
        .effect_row_ref = effect_row.evidenceRef(),
        .normal_form_ref = normal_form.evidenceRef(),
        .world_surface_ref = world_surface.evidenceRef(),
        .dependencies = normalization_dependencies[0..],
    });
    try std.testing.expectEqual(
        error.BoundaryNormalizationPolicyMismatch,
        provider_rewrite_disabled_certificate.check(provider_rewrite_disabled_policy, trace, redexes[0..], rules[0..], static_plans[0..], source_map, trace_map, evidence_map, effect_row, normal_form, world_surface),
    );
    var forged_surface = world_surface;
    forged_surface.source_map_ref = Evidence.refFor(Evidence.domains.boundary_elaboration_source_map, 0xBAD5_0A5E, .{ .label = "wrong-source-map" });
    forged_surface.surface_fingerprint = forged_surface.computeFingerprint();
    const forged_surface_certificate = Evidence.BoundaryNormalizationCertificate.init(.{
        .label = "normalization.forged_surface_certificate",
        .closure_certificate_ref = closure_certificate_ref,
        .target_policy_fingerprint = Evidence.BoundaryTargetPolicy.strictClosed().fingerprint(),
        .normalization_trace_ref = trace.evidenceRef(),
        .final_program_plan_hash = residual_ref.fingerprint,
        .source_map_ref = source_map.evidenceRef(),
        .trace_map_ref = trace_map.evidenceRef(),
        .evidence_map_ref = evidence_map.evidenceRef(),
        .effect_row_ref = effect_row.evidenceRef(),
        .normal_form_ref = normal_form.evidenceRef(),
        .world_surface_ref = forged_surface.evidenceRef(),
        .dependencies = (&[_]Evidence.Dependency{
            .{ .role = .normalization_trace, .ref = trace.evidenceRef() },
            .{ .role = .elaboration_source_map, .ref = source_map.evidenceRef() },
            .{ .role = .elaboration_trace_map, .ref = trace_map.evidenceRef() },
            .{ .role = .target_evidence_map, .ref = evidence_map.evidenceRef() },
            .{ .role = .elaboration_effect_row, .ref = effect_row.evidenceRef() },
            .{ .role = .normal_form, .ref = normal_form.evidenceRef() },
            .{ .role = .world_surface, .ref = forged_surface.evidenceRef() },
        })[0..],
    });
    try std.testing.expectEqual(
        error.BoundaryNormalizationCertificateMismatch,
        forged_surface_certificate.check(Evidence.BoundaryTargetPolicy.strictClosed(), trace, redexes[0..], rules[0..], static_plans[0..], source_map, trace_map, evidence_map, effect_row, normal_form, forged_surface),
    );

    const empty_world_ports_effect_row = Evidence.BoundaryElaborationEffectRow.init(.{
        .label = "normalization.empty_world_ports.effect_row",
        .source_program_ref = source_ref,
        .residual_program_ref = residual_ref,
        .normal_form = .world_ports_only,
        .source_effect_shapes = 1,
        .closed_effect_shapes = 1,
        .provider_program_links = 1,
    });
    const empty_world_ports_normal_form = Evidence.BoundaryNormalForm.init(
        "normalization.empty_world_ports.normal_form",
        .world_ports_only,
        closure_certificate_ref,
        empty_world_ports_effect_row.evidenceRef(),
        0,
    );
    const empty_world_ports_trace_deps = [_]Evidence.Dependency{
        .{ .role = .closure_certificate, .ref = closure_certificate_ref },
        .{ .role = .residual_program, .ref = residual_ref },
        .{ .role = .elaboration_source_map, .ref = source_map.evidenceRef() },
        .{ .role = .elaboration_effect_row, .ref = empty_world_ports_effect_row.evidenceRef() },
        .{ .role = .normal_form, .ref = empty_world_ports_normal_form.evidenceRef() },
    };
    const empty_world_ports_trace = Evidence.BoundaryNormalizationTrace.init(.{
        .label = "normalization.empty_world_ports.trace",
        .root_program_ref = source_ref,
        .closure_certificate_ref = closure_certificate_ref,
        .rewrite_steps = steps[0..],
        .eliminated_redex_refs = eliminated[0..],
        .final_program_plan_hash = residual_ref.fingerprint,
        .final_normal_form = .world_ports_only,
        .evidence_dependencies = empty_world_ports_trace_deps[0..],
    });
    const empty_world_ports_surface = Evidence.BoundaryWorldSurface.init(.{
        .label = "normalization.empty_world_ports.surface",
        .residual_program_label = "residual",
        .residual_program_ref = residual_ref,
        .elaboration_certificate_ref = Evidence.refFor(Evidence.domains.boundary_elaboration_certificate, 0xE1AB, .{ .label = "elaboration" }),
        .source_map_ref = source_map.evidenceRef(),
        .effect_row_ref = empty_world_ports_effect_row.evidenceRef(),
        .port_table_ref = Evidence.refFor(Evidence.domains.boundary_world_port_table, 0x7100, .{}),
        .value_table_ref = Evidence.refFor(Evidence.domains.boundary_world_value_table, 0x7101, .{}),
        .dispatch_table_ref = Evidence.refFor(Evidence.domains.boundary_world_dispatch_table, 0x7102, .{}),
        .profile_ref = Evidence.refFor(Evidence.domains.boundary_world_surface_profile, 0x7103, .{}),
        .replay_key_recipe_ref = Evidence.refFor(Evidence.domains.boundary_world_replay_key_recipe, 0x7104, .{}),
        .normal_form = .world_ports_only,
        .world_port_count = 0,
    });
    const empty_world_ports_certificate = Evidence.BoundaryNormalizationCertificate.init(.{
        .label = "normalization.empty_world_ports.certificate",
        .closure_certificate_ref = closure_certificate_ref,
        .target_policy_fingerprint = Evidence.BoundaryTargetPolicy.strictClosed().fingerprint(),
        .normalization_trace_ref = empty_world_ports_trace.evidenceRef(),
        .final_program_plan_hash = residual_ref.fingerprint,
        .source_map_ref = source_map.evidenceRef(),
        .trace_map_ref = trace_map.evidenceRef(),
        .evidence_map_ref = evidence_map.evidenceRef(),
        .effect_row_ref = empty_world_ports_effect_row.evidenceRef(),
        .normal_form_ref = empty_world_ports_normal_form.evidenceRef(),
        .world_surface_ref = empty_world_ports_surface.evidenceRef(),
        .dependencies = (&[_]Evidence.Dependency{
            .{ .role = .normalization_trace, .ref = empty_world_ports_trace.evidenceRef() },
            .{ .role = .elaboration_source_map, .ref = source_map.evidenceRef() },
            .{ .role = .elaboration_trace_map, .ref = trace_map.evidenceRef() },
            .{ .role = .target_evidence_map, .ref = evidence_map.evidenceRef() },
            .{ .role = .elaboration_effect_row, .ref = empty_world_ports_effect_row.evidenceRef() },
            .{ .role = .normal_form, .ref = empty_world_ports_normal_form.evidenceRef() },
            .{ .role = .world_surface, .ref = empty_world_ports_surface.evidenceRef() },
        })[0..],
    });
    try std.testing.expectEqual(
        error.BoundaryNormalizationCertificateMismatch,
        empty_world_ports_certificate.check(
            Evidence.BoundaryTargetPolicy.strictClosed(),
            empty_world_ports_trace,
            redexes[0..],
            rules[0..],
            static_plans[0..],
            source_map,
            trace_map,
            evidence_map,
            empty_world_ports_effect_row,
            empty_world_ports_normal_form,
            empty_world_ports_surface,
        ),
    );

    const blockerless_partial_effect_row = Evidence.BoundaryElaborationEffectRow.init(.{
        .label = "normalization.blockerless_partial.effect_row",
        .source_program_ref = source_ref,
        .residual_program_ref = residual_ref,
        .normal_form = .partial_with_blockers,
        .source_effect_shapes = 1,
        .closed_effect_shapes = 1,
        .provider_program_links = 1,
    });
    const blockerless_partial_normal_form = Evidence.BoundaryNormalForm.init(
        "normalization.blockerless_partial.normal_form",
        .partial_with_blockers,
        closure_certificate_ref,
        blockerless_partial_effect_row.evidenceRef(),
        0,
    );
    const blockerless_partial_trace_deps = [_]Evidence.Dependency{
        .{ .role = .closure_certificate, .ref = closure_certificate_ref },
        .{ .role = .residual_program, .ref = residual_ref },
        .{ .role = .elaboration_source_map, .ref = source_map.evidenceRef() },
        .{ .role = .elaboration_effect_row, .ref = blockerless_partial_effect_row.evidenceRef() },
        .{ .role = .normal_form, .ref = blockerless_partial_normal_form.evidenceRef() },
    };
    const blockerless_partial_trace = Evidence.BoundaryNormalizationTrace.init(.{
        .label = "normalization.blockerless_partial.trace",
        .root_program_ref = source_ref,
        .closure_certificate_ref = closure_certificate_ref,
        .rewrite_steps = steps[0..],
        .eliminated_redex_refs = eliminated[0..],
        .final_program_plan_hash = residual_ref.fingerprint,
        .final_normal_form = .partial_with_blockers,
        .evidence_dependencies = blockerless_partial_trace_deps[0..],
    });
    const blockerless_partial_surface = Evidence.BoundaryWorldSurface.init(.{
        .label = "normalization.blockerless_partial.surface",
        .residual_program_label = "residual",
        .residual_program_ref = residual_ref,
        .elaboration_certificate_ref = Evidence.refFor(Evidence.domains.boundary_elaboration_certificate, 0xE1AB, .{ .label = "elaboration" }),
        .source_map_ref = source_map.evidenceRef(),
        .effect_row_ref = blockerless_partial_effect_row.evidenceRef(),
        .port_table_ref = Evidence.refFor(Evidence.domains.boundary_world_port_table, 0x7100, .{}),
        .value_table_ref = Evidence.refFor(Evidence.domains.boundary_world_value_table, 0x7101, .{}),
        .dispatch_table_ref = Evidence.refFor(Evidence.domains.boundary_world_dispatch_table, 0x7102, .{}),
        .profile_ref = Evidence.refFor(Evidence.domains.boundary_world_surface_profile, 0x7103, .{}),
        .replay_key_recipe_ref = Evidence.refFor(Evidence.domains.boundary_world_replay_key_recipe, 0x7104, .{}),
        .normal_form = .partial_with_blockers,
        .world_port_count = 0,
    });
    const blockerless_partial_certificate = Evidence.BoundaryNormalizationCertificate.init(.{
        .label = "normalization.blockerless_partial.certificate",
        .closure_certificate_ref = closure_certificate_ref,
        .target_policy_fingerprint = Evidence.BoundaryTargetPolicy.strictClosed().fingerprint(),
        .normalization_trace_ref = blockerless_partial_trace.evidenceRef(),
        .final_program_plan_hash = residual_ref.fingerprint,
        .source_map_ref = source_map.evidenceRef(),
        .trace_map_ref = trace_map.evidenceRef(),
        .evidence_map_ref = evidence_map.evidenceRef(),
        .effect_row_ref = blockerless_partial_effect_row.evidenceRef(),
        .normal_form_ref = blockerless_partial_normal_form.evidenceRef(),
        .world_surface_ref = blockerless_partial_surface.evidenceRef(),
        .dependencies = (&[_]Evidence.Dependency{
            .{ .role = .normalization_trace, .ref = blockerless_partial_trace.evidenceRef() },
            .{ .role = .elaboration_source_map, .ref = source_map.evidenceRef() },
            .{ .role = .elaboration_trace_map, .ref = trace_map.evidenceRef() },
            .{ .role = .target_evidence_map, .ref = evidence_map.evidenceRef() },
            .{ .role = .elaboration_effect_row, .ref = blockerless_partial_effect_row.evidenceRef() },
            .{ .role = .normal_form, .ref = blockerless_partial_normal_form.evidenceRef() },
            .{ .role = .world_surface, .ref = blockerless_partial_surface.evidenceRef() },
        })[0..],
    });
    try std.testing.expectEqual(
        error.BoundaryNormalizationCertificateMismatch,
        blockerless_partial_certificate.check(
            Evidence.BoundaryTargetPolicy.strictClosed(),
            blockerless_partial_trace,
            redexes[0..],
            rules[0..],
            static_plans[0..],
            source_map,
            trace_map,
            evidence_map,
            blockerless_partial_effect_row,
            blockerless_partial_normal_form,
            blockerless_partial_surface,
        ),
    );
    const missing_dependency_trace = Evidence.BoundaryNormalizationTrace.init(.{
        .label = "normalization.missing_dependency_trace",
        .root_program_ref = source_ref,
        .closure_certificate_ref = closure_certificate_ref,
        .rewrite_steps = steps[0..],
        .eliminated_redex_refs = eliminated[0..],
        .final_program_plan_hash = residual_ref.fingerprint,
        .final_normal_form = .strict_closed,
    });
    const missing_dependency_certificate = Evidence.BoundaryNormalizationCertificate.init(.{
        .label = "normalization.missing_dependency_certificate",
        .closure_certificate_ref = closure_certificate_ref,
        .target_policy_fingerprint = Evidence.BoundaryTargetPolicy.strictClosed().fingerprint(),
        .normalization_trace_ref = missing_dependency_trace.evidenceRef(),
        .final_program_plan_hash = residual_ref.fingerprint,
        .source_map_ref = source_map.evidenceRef(),
        .trace_map_ref = trace_map.evidenceRef(),
        .evidence_map_ref = evidence_map.evidenceRef(),
        .effect_row_ref = effect_row.evidenceRef(),
        .normal_form_ref = normal_form.evidenceRef(),
        .world_surface_ref = world_surface.evidenceRef(),
        .dependencies = (&[_]Evidence.Dependency{
            .{ .role = .normalization_trace, .ref = missing_dependency_trace.evidenceRef() },
            .{ .role = .elaboration_source_map, .ref = source_map.evidenceRef() },
            .{ .role = .elaboration_trace_map, .ref = trace_map.evidenceRef() },
            .{ .role = .target_evidence_map, .ref = evidence_map.evidenceRef() },
            .{ .role = .elaboration_effect_row, .ref = effect_row.evidenceRef() },
            .{ .role = .normal_form, .ref = normal_form.evidenceRef() },
            .{ .role = .world_surface, .ref = world_surface.evidenceRef() },
        })[0..],
    });
    try std.testing.expectEqual(
        error.BoundaryNormalizationCertificateMismatch,
        missing_dependency_certificate.check(Evidence.BoundaryTargetPolicy.strictClosed(), missing_dependency_trace, redexes[0..], rules[0..], static_plans[0..], source_map, trace_map, evidence_map, effect_row, normal_form, world_surface),
    );
    const forged_builder_step = Evidence.BoundaryNormalizationRewriteStep.init(.{
        .step_index = 0,
        .redex_ref = redex.evidenceRef(),
        .rewrite_rule_ref = rule.evidenceRef(),
        .selected_static_treaty_plan_ref = static_plan.evidenceRef(),
        .source_effect_shape_ref = shape.evidenceRef(),
        .input_program_plan_hash = source_ref.fingerprint,
        .output_program_plan_hash = residual_ref.fingerprint,
        .builder_state_fingerprint = route_lowering_fingerprint + 1,
        .provider_program_ref = provider_program_ref,
        .provider_offer_ref = offer_ref,
        .summary = "provider_program_call",
    });
    const forged_builder_steps = [_]Evidence.BoundaryNormalizationRewriteStep{forged_builder_step};
    const forged_builder_trace = Evidence.BoundaryNormalizationTrace.init(.{
        .label = "normalization.forged_builder_trace",
        .root_program_ref = source_ref,
        .closure_certificate_ref = closure_certificate_ref,
        .rewrite_steps = forged_builder_steps[0..],
        .eliminated_redex_refs = eliminated[0..],
        .final_program_plan_hash = residual_ref.fingerprint,
        .final_normal_form = .strict_closed,
        .evidence_dependencies = trace_deps[0..],
    });
    const forged_builder_certificate = Evidence.BoundaryNormalizationCertificate.init(.{
        .label = "normalization.forged_builder_certificate",
        .closure_certificate_ref = closure_certificate_ref,
        .target_policy_fingerprint = Evidence.BoundaryTargetPolicy.strictClosed().fingerprint(),
        .normalization_trace_ref = forged_builder_trace.evidenceRef(),
        .final_program_plan_hash = residual_ref.fingerprint,
        .source_map_ref = source_map.evidenceRef(),
        .trace_map_ref = trace_map.evidenceRef(),
        .evidence_map_ref = evidence_map.evidenceRef(),
        .effect_row_ref = effect_row.evidenceRef(),
        .normal_form_ref = normal_form.evidenceRef(),
        .world_surface_ref = world_surface.evidenceRef(),
        .dependencies = (&[_]Evidence.Dependency{
            .{ .role = .normalization_trace, .ref = forged_builder_trace.evidenceRef() },
            .{ .role = .elaboration_source_map, .ref = source_map.evidenceRef() },
            .{ .role = .elaboration_trace_map, .ref = trace_map.evidenceRef() },
            .{ .role = .target_evidence_map, .ref = evidence_map.evidenceRef() },
            .{ .role = .elaboration_effect_row, .ref = effect_row.evidenceRef() },
            .{ .role = .normal_form, .ref = normal_form.evidenceRef() },
            .{ .role = .world_surface, .ref = world_surface.evidenceRef() },
        })[0..],
    });
    try std.testing.expectEqual(
        error.BoundaryNormalizationCertificateMismatch,
        forged_builder_certificate.check(Evidence.BoundaryTargetPolicy.strictClosed(), forged_builder_trace, redexes[0..], rules[0..], static_plans[0..], source_map, trace_map, evidence_map, effect_row, normal_form, world_surface),
    );
    const forged_coordinate_redex = Evidence.BoundaryNormalizationRedex.init(.{
        .label = "approval.request",
        .source_effect_shape_ref = shape.evidenceRef(),
        .coordinates = .{ .function_index = 0, .block_index = 0, .instruction_index = 7, .site_index = 0 },
        .kind = .operation_site,
        .selected_static_treaty_plan_ref = static_plan.evidenceRef(),
        .current_program_plan_ref = source_ref,
        .semantic_body = .boundary_program,
        .expected_lowering_kind = .provider_program_call,
        .evidence_dependencies = redex_dependencies[0..],
    });
    const forged_coordinate_step = Evidence.BoundaryNormalizationRewriteStep.init(.{
        .step_index = 0,
        .redex_ref = forged_coordinate_redex.evidenceRef(),
        .rewrite_rule_ref = rule.evidenceRef(),
        .selected_static_treaty_plan_ref = static_plan.evidenceRef(),
        .source_effect_shape_ref = shape.evidenceRef(),
        .input_program_plan_hash = source_ref.fingerprint,
        .output_program_plan_hash = residual_ref.fingerprint,
        .builder_state_fingerprint = route_lowering_fingerprint,
        .provider_program_ref = provider_program_ref,
        .provider_offer_ref = offer_ref,
        .summary = "provider_program_call",
    });
    const forged_coordinate_steps = [_]Evidence.BoundaryNormalizationRewriteStep{forged_coordinate_step};
    const forged_coordinate_eliminated = [_]Evidence.Ref{forged_coordinate_redex.evidenceRef()};
    const forged_coordinate_trace = Evidence.BoundaryNormalizationTrace.init(.{
        .label = "normalization.forged_coordinate_trace",
        .root_program_ref = source_ref,
        .closure_certificate_ref = closure_certificate_ref,
        .rewrite_steps = forged_coordinate_steps[0..],
        .eliminated_redex_refs = forged_coordinate_eliminated[0..],
        .final_program_plan_hash = residual_ref.fingerprint,
        .final_normal_form = .strict_closed,
        .evidence_dependencies = trace_deps[0..],
    });
    const forged_coordinate_certificate = Evidence.BoundaryNormalizationCertificate.init(.{
        .label = "normalization.forged_coordinate_certificate",
        .closure_certificate_ref = closure_certificate_ref,
        .target_policy_fingerprint = Evidence.BoundaryTargetPolicy.strictClosed().fingerprint(),
        .normalization_trace_ref = forged_coordinate_trace.evidenceRef(),
        .final_program_plan_hash = residual_ref.fingerprint,
        .source_map_ref = source_map.evidenceRef(),
        .trace_map_ref = trace_map.evidenceRef(),
        .evidence_map_ref = evidence_map.evidenceRef(),
        .effect_row_ref = effect_row.evidenceRef(),
        .normal_form_ref = normal_form.evidenceRef(),
        .world_surface_ref = world_surface.evidenceRef(),
        .dependencies = (&[_]Evidence.Dependency{
            .{ .role = .normalization_trace, .ref = forged_coordinate_trace.evidenceRef() },
            .{ .role = .elaboration_source_map, .ref = source_map.evidenceRef() },
            .{ .role = .elaboration_trace_map, .ref = trace_map.evidenceRef() },
            .{ .role = .target_evidence_map, .ref = evidence_map.evidenceRef() },
            .{ .role = .elaboration_effect_row, .ref = effect_row.evidenceRef() },
            .{ .role = .normal_form, .ref = normal_form.evidenceRef() },
            .{ .role = .world_surface, .ref = world_surface.evidenceRef() },
        })[0..],
    });
    const forged_coordinate_redexes = [_]Evidence.BoundaryNormalizationRedex{forged_coordinate_redex};
    try std.testing.expectEqual(
        error.BoundaryNormalizationCertificateMismatch,
        forged_coordinate_certificate.check(Evidence.BoundaryTargetPolicy.strictClosed(), forged_coordinate_trace, forged_coordinate_redexes[0..], rules[0..], static_plans[0..], source_map, trace_map, evidence_map, effect_row, normal_form, world_surface),
    );
    const forged_semantic_redex = Evidence.BoundaryNormalizationRedex.init(.{
        .label = "approval.request",
        .source_effect_shape_ref = shape.evidenceRef(),
        .coordinates = .{ .function_index = 0, .block_index = 0, .instruction_index = 0, .site_index = 0 },
        .kind = .operation_site,
        .selected_static_treaty_plan_ref = static_plan.evidenceRef(),
        .current_program_plan_ref = source_ref,
        .semantic_body = .declarative,
        .expected_lowering_kind = .provider_program_call,
        .evidence_dependencies = redex_dependencies[0..],
    });
    const forged_semantic_step = Evidence.BoundaryNormalizationRewriteStep.init(.{
        .step_index = 0,
        .redex_ref = forged_semantic_redex.evidenceRef(),
        .rewrite_rule_ref = rule.evidenceRef(),
        .selected_static_treaty_plan_ref = static_plan.evidenceRef(),
        .source_effect_shape_ref = shape.evidenceRef(),
        .input_program_plan_hash = source_ref.fingerprint,
        .output_program_plan_hash = residual_ref.fingerprint,
        .builder_state_fingerprint = route_lowering_fingerprint,
        .provider_program_ref = provider_program_ref,
        .provider_offer_ref = offer_ref,
        .summary = "provider_program_call",
    });
    const forged_semantic_steps = [_]Evidence.BoundaryNormalizationRewriteStep{forged_semantic_step};
    const forged_semantic_eliminated = [_]Evidence.Ref{forged_semantic_redex.evidenceRef()};
    const forged_semantic_trace = Evidence.BoundaryNormalizationTrace.init(.{
        .label = "normalization.forged_semantic_trace",
        .root_program_ref = source_ref,
        .closure_certificate_ref = closure_certificate_ref,
        .rewrite_steps = forged_semantic_steps[0..],
        .eliminated_redex_refs = forged_semantic_eliminated[0..],
        .final_program_plan_hash = residual_ref.fingerprint,
        .final_normal_form = .strict_closed,
        .evidence_dependencies = trace_deps[0..],
    });
    const forged_semantic_certificate = Evidence.BoundaryNormalizationCertificate.init(.{
        .label = "normalization.forged_semantic_certificate",
        .closure_certificate_ref = closure_certificate_ref,
        .target_policy_fingerprint = Evidence.BoundaryTargetPolicy.strictClosed().fingerprint(),
        .normalization_trace_ref = forged_semantic_trace.evidenceRef(),
        .final_program_plan_hash = residual_ref.fingerprint,
        .source_map_ref = source_map.evidenceRef(),
        .trace_map_ref = trace_map.evidenceRef(),
        .evidence_map_ref = evidence_map.evidenceRef(),
        .effect_row_ref = effect_row.evidenceRef(),
        .normal_form_ref = normal_form.evidenceRef(),
        .world_surface_ref = world_surface.evidenceRef(),
        .dependencies = (&[_]Evidence.Dependency{
            .{ .role = .normalization_trace, .ref = forged_semantic_trace.evidenceRef() },
            .{ .role = .elaboration_source_map, .ref = source_map.evidenceRef() },
            .{ .role = .elaboration_trace_map, .ref = trace_map.evidenceRef() },
            .{ .role = .target_evidence_map, .ref = evidence_map.evidenceRef() },
            .{ .role = .elaboration_effect_row, .ref = effect_row.evidenceRef() },
            .{ .role = .normal_form, .ref = normal_form.evidenceRef() },
            .{ .role = .world_surface, .ref = world_surface.evidenceRef() },
        })[0..],
    });
    const forged_semantic_redexes = [_]Evidence.BoundaryNormalizationRedex{forged_semantic_redex};
    try std.testing.expectEqual(
        error.BoundaryNormalizationCertificateMismatch,
        forged_semantic_certificate.check(Evidence.BoundaryTargetPolicy.strictClosed(), forged_semantic_trace, forged_semantic_redexes[0..], rules[0..], static_plans[0..], source_map, trace_map, evidence_map, effect_row, normal_form, world_surface),
    );
    var stale_view_certificate = certificate;
    stale_view_certificate.evidence_view.subject_ref = residual_ref;
    try std.testing.expectEqual(
        error.BoundaryNormalizationCertificateMismatch,
        stale_view_certificate.check(Evidence.BoundaryTargetPolicy.strictClosed(), trace, redexes[0..], rules[0..], static_plans[0..], source_map, trace_map, evidence_map, effect_row, normal_form, world_surface),
    );

    var stale_source_map = source_map;
    stale_source_map.label = "normalization.stale_source_map";
    try std.testing.expectEqual(
        error.BoundaryNormalizationCertificateMismatch,
        certificate.check(
            Evidence.BoundaryTargetPolicy.strictClosed(),
            trace,
            redexes[0..],
            rules[0..],
            static_plans[0..],
            stale_source_map,
            trace_map,
            evidence_map,
            effect_row,
            normal_form,
            world_surface,
        ),
    );

    const unsupported_refs = [_]Evidence.Ref{redex.evidenceRef()};
    const unsupported_trace = Evidence.BoundaryNormalizationTrace.init(.{
        .label = "normalization.unsupported_trace",
        .root_program_ref = source_ref,
        .closure_certificate_ref = closure_certificate_ref,
        .rewrite_steps = steps[0..],
        .unsupported_redex_refs = unsupported_refs[0..],
        .final_program_plan_hash = residual_ref.fingerprint,
        .final_normal_form = .strict_closed,
        .evidence_dependencies = trace_deps[0..],
    });
    const certificate_without_blockers = Evidence.BoundaryNormalizationCertificate.init(.{
        .label = "normalization.omitted_blocker_certificate",
        .closure_certificate_ref = closure_certificate_ref,
        .target_policy_fingerprint = Evidence.BoundaryTargetPolicy.strictClosed().fingerprint(),
        .normalization_trace_ref = unsupported_trace.evidenceRef(),
        .final_program_plan_hash = residual_ref.fingerprint,
        .source_map_ref = source_map.evidenceRef(),
        .trace_map_ref = trace_map.evidenceRef(),
        .evidence_map_ref = evidence_map.evidenceRef(),
        .effect_row_ref = effect_row.evidenceRef(),
        .normal_form_ref = normal_form.evidenceRef(),
        .world_surface_ref = world_surface.evidenceRef(),
        .dependencies = (&[_]Evidence.Dependency{
            .{ .role = .normalization_trace, .ref = unsupported_trace.evidenceRef() },
            .{ .role = .elaboration_source_map, .ref = source_map.evidenceRef() },
            .{ .role = .elaboration_trace_map, .ref = trace_map.evidenceRef() },
            .{ .role = .target_evidence_map, .ref = evidence_map.evidenceRef() },
            .{ .role = .elaboration_effect_row, .ref = effect_row.evidenceRef() },
            .{ .role = .normal_form, .ref = normal_form.evidenceRef() },
            .{ .role = .world_surface, .ref = world_surface.evidenceRef() },
        })[0..],
    });
    try std.testing.expectEqual(
        error.BoundaryNormalizationCertificateMismatch,
        certificate_without_blockers.check(
            Evidence.BoundaryTargetPolicy.strictClosed(),
            unsupported_trace,
            redexes[0..],
            rules[0..],
            static_plans[0..],
            source_map,
            trace_map,
            evidence_map,
            effect_row,
            normal_form,
            world_surface,
        ),
    );

    const blocked_plan_blocker = Evidence.BoundaryClosureBlocker{
        .tag = .unsupported_shape_planning,
        .subject = shape.evidenceRef(),
        .summary = "normalization blocked source shape",
    };
    const blocked_blocker_ref = Evidence.refForBoundaryClosureBlocker(blocked_plan_blocker.toEvidenceBlocker());
    const blocked_static_plan = Evidence.BoundaryStaticTreatyPlan.init(.{
        .label = "normalization.blocked_plan",
        .source_shape = shape,
        .selected_semantic_body = .unknown,
        .blockers = &.{blocked_plan_blocker},
    });
    const blocked_static_plans = [_]Evidence.BoundaryStaticTreatyPlan{blocked_static_plan};
    var blocked_source_entry = source_map_entries[0];
    blocked_source_entry.disposition = .blocked;
    blocked_source_entry.provider_program_ref = null;
    blocked_source_entry.static_treaty_plan_ref = blocked_static_plan.evidenceRef();
    blocked_source_entry.blocker_ref = null;
    const blocked_source_map_entries = [_]Evidence.BoundaryElaborationSourceMap.Entry{blocked_source_entry};
    const blocked_source_map = Evidence.BoundaryElaborationSourceMap.init("normalization.blocked_source_map", blocked_source_map_entries[0..], &.{});
    const blocked_route_lowering_fingerprint = Evidence.boundaryNormalizationRouteLoweringFingerprint(blocked_source_entry, residual_ref.fingerprint);
    const blocked_redex = Evidence.BoundaryNormalizationRedex.init(.{
        .label = "approval.request",
        .source_effect_shape_ref = shape.evidenceRef(),
        .coordinates = .{ .function_index = 0, .block_index = 0, .instruction_index = 0, .site_index = 0 },
        .kind = .operation_site,
        .selected_static_treaty_plan_ref = blocked_static_plan.evidenceRef(),
        .current_program_plan_ref = source_ref,
        .semantic_body = .unknown,
        .expected_lowering_kind = .unsupported,
        .evidence_dependencies = redex_dependencies[0..],
    });
    const blocked_rule = Evidence.BoundaryNormalizationRewriteRule.init(.{
        .label = "approval.request",
        .kind = .unsupported,
        .evidence_dependencies = rule_dependencies[0..],
        .produced_source_map_entries = 1,
        .produced_trace_map_entries = 1,
        .produced_effect_row_entries = 1,
        .blocker_refs = &.{blocked_blocker_ref},
    });
    const blocked_step = Evidence.BoundaryNormalizationRewriteStep.init(.{
        .step_index = 0,
        .redex_ref = blocked_redex.evidenceRef(),
        .rewrite_rule_ref = blocked_rule.evidenceRef(),
        .selected_static_treaty_plan_ref = blocked_static_plan.evidenceRef(),
        .source_effect_shape_ref = shape.evidenceRef(),
        .input_program_plan_hash = source_ref.fingerprint,
        .output_program_plan_hash = residual_ref.fingerprint,
        .builder_state_fingerprint = blocked_route_lowering_fingerprint,
        .blocker_refs = &.{blocked_blocker_ref},
        .summary = "unsupported",
    });
    const blocked_redexes = [_]Evidence.BoundaryNormalizationRedex{blocked_redex};
    const blocked_rules = [_]Evidence.BoundaryNormalizationRewriteRule{blocked_rule};
    const blocked_steps = [_]Evidence.BoundaryNormalizationRewriteStep{blocked_step};
    const blocked_unsupported_refs = [_]Evidence.Ref{blocked_redex.evidenceRef()};
    const blocked_effect_row = Evidence.BoundaryElaborationEffectRow.init(.{
        .label = "normalization.blocked_effect_row",
        .source_program_ref = source_ref,
        .residual_program_ref = residual_ref,
        .normal_form = .partial_with_blockers,
        .source_effect_shapes = 1,
        .unsupported_shapes = 1,
        .blockers = 1,
    });
    const blocked_normal_form = Evidence.BoundaryNormalForm.init("normalization.blocked_normal_form", .partial_with_blockers, closure_certificate_ref, blocked_effect_row.evidenceRef(), 1);
    const blocked_trace_deps = [_]Evidence.Dependency{
        .{ .role = .closure_certificate, .ref = closure_certificate_ref },
        .{ .role = .residual_program, .ref = residual_ref },
        .{ .role = .elaboration_source_map, .ref = blocked_source_map.evidenceRef() },
        .{ .role = .elaboration_effect_row, .ref = blocked_effect_row.evidenceRef() },
        .{ .role = .normal_form, .ref = blocked_normal_form.evidenceRef() },
    };
    const blocked_trace = Evidence.BoundaryNormalizationTrace.init(.{
        .label = "normalization.blocked_trace",
        .root_program_ref = source_ref,
        .closure_certificate_ref = closure_certificate_ref,
        .rewrite_steps = blocked_steps[0..],
        .unsupported_redex_refs = blocked_unsupported_refs[0..],
        .final_program_plan_hash = residual_ref.fingerprint,
        .final_normal_form = .partial_with_blockers,
        .evidence_dependencies = blocked_trace_deps[0..],
    });
    const blocked_world_surface = Evidence.BoundaryWorldSurface.init(.{
        .label = "normalization.blocked_world_surface",
        .residual_program_label = "residual",
        .residual_program_ref = residual_ref,
        .elaboration_certificate_ref = Evidence.refFor(Evidence.domains.boundary_elaboration_certificate, 0xE1AB, .{ .label = "elaboration" }),
        .source_map_ref = blocked_source_map.evidenceRef(),
        .effect_row_ref = blocked_effect_row.evidenceRef(),
        .port_table_ref = Evidence.refFor(Evidence.domains.boundary_world_port_table, 0x7100, .{}),
        .value_table_ref = Evidence.refFor(Evidence.domains.boundary_world_value_table, 0x7101, .{}),
        .dispatch_table_ref = Evidence.refFor(Evidence.domains.boundary_world_dispatch_table, 0x7102, .{}),
        .profile_ref = Evidence.refFor(Evidence.domains.boundary_world_surface_profile, 0x7103, .{}),
        .replay_key_recipe_ref = Evidence.refFor(Evidence.domains.boundary_world_replay_key_recipe, 0x7104, .{}),
        .normal_form = .partial_with_blockers,
        .world_port_count = 0,
    });
    const blocked_source_certificate = Evidence.BoundaryNormalizationCertificate.init(.{
        .label = "normalization.blocked_source_certificate",
        .closure_certificate_ref = closure_certificate_ref,
        .target_policy_fingerprint = Evidence.BoundaryTargetPolicy.strictClosed().fingerprint(),
        .normalization_trace_ref = blocked_trace.evidenceRef(),
        .final_program_plan_hash = residual_ref.fingerprint,
        .source_map_ref = blocked_source_map.evidenceRef(),
        .trace_map_ref = trace_map.evidenceRef(),
        .evidence_map_ref = evidence_map.evidenceRef(),
        .effect_row_ref = blocked_effect_row.evidenceRef(),
        .normal_form_ref = blocked_normal_form.evidenceRef(),
        .world_surface_ref = blocked_world_surface.evidenceRef(),
        .blocker_refs = &.{blocked_blocker_ref},
        .dependencies = (&[_]Evidence.Dependency{
            .{ .role = .normalization_trace, .ref = blocked_trace.evidenceRef() },
            .{ .role = .elaboration_source_map, .ref = blocked_source_map.evidenceRef() },
            .{ .role = .elaboration_trace_map, .ref = trace_map.evidenceRef() },
            .{ .role = .target_evidence_map, .ref = evidence_map.evidenceRef() },
            .{ .role = .elaboration_effect_row, .ref = blocked_effect_row.evidenceRef() },
            .{ .role = .normal_form, .ref = blocked_normal_form.evidenceRef() },
            .{ .role = .world_surface, .ref = blocked_world_surface.evidenceRef() },
        })[0..],
    });
    const blocked_source_certificate_without_blocker_refs = Evidence.BoundaryNormalizationCertificate.init(.{
        .label = "normalization.blocked_source_certificate.without_blocker_refs",
        .closure_certificate_ref = closure_certificate_ref,
        .target_policy_fingerprint = Evidence.BoundaryTargetPolicy.auditOnly().fingerprint(),
        .normalization_trace_ref = blocked_trace.evidenceRef(),
        .final_program_plan_hash = residual_ref.fingerprint,
        .source_map_ref = blocked_source_map.evidenceRef(),
        .trace_map_ref = trace_map.evidenceRef(),
        .evidence_map_ref = evidence_map.evidenceRef(),
        .effect_row_ref = blocked_effect_row.evidenceRef(),
        .normal_form_ref = blocked_normal_form.evidenceRef(),
        .world_surface_ref = blocked_world_surface.evidenceRef(),
        .dependencies = (&[_]Evidence.Dependency{
            .{ .role = .normalization_trace, .ref = blocked_trace.evidenceRef() },
            .{ .role = .elaboration_source_map, .ref = blocked_source_map.evidenceRef() },
            .{ .role = .elaboration_trace_map, .ref = trace_map.evidenceRef() },
            .{ .role = .target_evidence_map, .ref = evidence_map.evidenceRef() },
            .{ .role = .elaboration_effect_row, .ref = blocked_effect_row.evidenceRef() },
            .{ .role = .normal_form, .ref = blocked_normal_form.evidenceRef() },
            .{ .role = .world_surface, .ref = blocked_world_surface.evidenceRef() },
        })[0..],
    });
    try std.testing.expectEqual(
        error.BoundaryNormalizationCertificateMismatch,
        blocked_source_certificate_without_blocker_refs.check(
            Evidence.BoundaryTargetPolicy.auditOnly(),
            blocked_trace,
            blocked_redexes[0..],
            blocked_rules[0..],
            blocked_static_plans[0..],
            blocked_source_map,
            trace_map,
            evidence_map,
            blocked_effect_row,
            blocked_normal_form,
            blocked_world_surface,
        ),
    );
    try std.testing.expectEqual(
        error.BoundaryNormalizationBlocked,
        blocked_source_certificate.check(
            Evidence.BoundaryTargetPolicy.strictClosed(),
            blocked_trace,
            blocked_redexes[0..],
            blocked_rules[0..],
            blocked_static_plans[0..],
            blocked_source_map,
            trace_map,
            evidence_map,
            blocked_effect_row,
            blocked_normal_form,
            blocked_world_surface,
        ),
    );
}

test "boundary normalization input validates checked closure and target policy compatibility" {
    const validates_and_rejects_mismatch = comptime blk: {
        @setEvalBranchQuota(200_000);
        const Closure = Program.BoundaryClosure;
        const Elaboration = Closure.Elaboration;
        const source_ref = Evidence.refFor(Evidence.domains.program_plan, Program.compiled_plan.hash(), .{ .label = Program.contract.label });
        const graph = Closure.Graph.init("normalization-input-graph", &.{}, &.{}, &.{});
        const report = Closure.Report.init(.{
            .graph_fingerprint = graph.fingerprint,
            .root_program_refs = &.{source_ref},
        });
        const certificate = Closure.Certificate.init(report, graph, Closure.Policy.auditOnly(), &.{});
        const target_policy = Elaboration.Target.Policy.auditOnly();
        const input = Elaboration.Input{
            .closure_graph = graph,
            .closure_report = report,
            .closure_certificate = certificate,
            .source_program_ref = source_ref,
            .policy = target_policy.toElaborationPolicy(),
        };
        const normalization_input = Elaboration.Target.Normalization.Input.fromElaboration(input, target_policy);
        normalization_input.validate(input) catch break :blk false;
        const routes = Elaboration.Target.Normalization.routesFor(normalization_input);
        if (routes.len != 0) break :blk false;
        var mismatched_policy = normalization_input;
        mismatched_policy.target_policy = Elaboration.Target.Policy.strictClosed();
        const policy_mismatch_rejected = mismatched_policy.validate(input) catch |err| err == error.BoundaryElaborationPolicyMismatch;
        if (!policy_mismatch_rejected) break :blk false;
        var mismatched = normalization_input;
        mismatched.root_program_ref = Evidence.refFor(Evidence.domains.program_plan, 0xBAD, .{ .label = "wrong-root" });
        mismatched.validate(input) catch |err| break :blk err == error.BoundaryElaborationRootRefMismatch;
        break :blk false;
    };
    try std.testing.expect(validates_and_rejects_mismatch);
    try std.testing.expect(Evidence.BoundaryNormalizationPolicy.strictClosed().fingerprint() != Evidence.BoundaryNormalizationPolicy.worldBoundary().fingerprint());
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
    const after_closure_shape = Evidence.BoundaryEffectShape.init(.{
        .program_label = "closure-root",
        .kind = .after,
        .site_index = 4,
        .site_fingerprint = 0x3333,
        .protocol_label = "approval",
        .protocol_op_fingerprint = 0x3333,
    });
    const ordered_shapes = [_]Evidence.BoundaryEffectShape{ closure_shape, after_closure_shape };
    const reversed_shapes = [_]Evidence.BoundaryEffectShape{ after_closure_shape, closure_shape };
    try std.testing.expectEqual(
        Evidence.fingerprintBoundaryEffectShapeSet(ordered_shapes[0..]),
        Evidence.fingerprintBoundaryEffectShapeSet(reversed_shapes[0..]),
    );

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

test "boundary elaboration foundational refs and certificate evidence are deterministic" {
    const Closure = Program.BoundaryClosure;
    const Elaboration = Program.BoundaryClosure.Elaboration;
    const source_ref = Evidence.refFor(Evidence.domains.program_plan, 0xE1A801, .{ .label = "source" });
    const residual_ref = Evidence.refFor(Evidence.domains.program_plan, 0xE1A802, .{ .label = "residual" });
    const closure_graph_ref = Evidence.refFor(Evidence.domains.boundary_closure_graph, 0xE1A803, .{ .label = "closure-graph" });
    const closure_report_ref = Evidence.refFor(Evidence.domains.boundary_closure_report, 0xE1A804, .{ .label = "closure-report" });
    const closure_certificate_ref = Evidence.refFor(Evidence.domains.boundary_closure_certificate, 0xE1A805, .{
        .format_version = Evidence.domains.boundary_closure_certificate.format_version,
        .label = "closure-certificate",
    });
    const source_shape = Closure.EffectShape.init(.{
        .program_label = "source",
        .plan_hash = source_ref.fingerprint,
        .kind = .operation,
        .site_index = 0,
        .protocol_label = "root",
    });
    const source_shape_ref = source_shape.evidenceRef();
    const static_plan_dependencies = [_]Evidence.Dependency{.{
        .role = .residual_program,
        .ref = residual_ref,
    }};
    const static_plan = Closure.StaticTreatyPlan.init(.{
        .label = "root.plan",
        .source_shape = source_shape,
        .selected_semantic_body = .declarative,
        .dependencies = static_plan_dependencies[0..],
    });
    const static_plan_ref = static_plan.evidenceRef();
    const static_plans = [_]Closure.StaticTreatyPlan{static_plan};
    const source_map_entries = [_]Elaboration.SourceMap.Entry{.{
        .source_ref = source_shape_ref,
        .residual_ref = residual_ref,
        .source_site_index = 0,
        .static_treaty_plan_ref = static_plan_ref,
        .disposition = .preserved,
        .label = "root",
    }};
    const source_map = Elaboration.SourceMap.init("strict-elaboration-map", source_map_entries[0..], &.{});
    const trace_entries = [_]Elaboration.TraceMap.Entry{.{ .source_ref = source_shape_ref, .residual_ref = residual_ref, .trace_label = "root" }};
    const trace_map = Elaboration.TraceMap.init("strict-elaboration-trace", trace_entries[0..]);
    const effect_row = Elaboration.EffectRow.init(.{
        .label = "strict-elaboration-row",
        .source_program_ref = source_ref,
        .residual_program_ref = residual_ref,
        .normal_form = .strict_closed,
        .source_effect_shapes = 1,
        .closed_effect_shapes = 1,
    });
    const normal_form = Elaboration.NormalForm.init("strict-elaboration-normal-form", .strict_closed, closure_certificate_ref, effect_row.evidenceRef(), 0);
    var policy = Elaboration.Policy.strictStatic();
    policy.require_program_backed_providers_for_internal_routes = false;
    try std.testing.expectEqual(Evidence.domains.boundary_elaboration_policy.id, policy.policySummary().policy_domain);
    const dependencies = [_]Evidence.Dependency{
        .{ .role = .closure_certificate, .ref = closure_certificate_ref },
        .{ .role = .elaboration_source_map, .ref = source_map.evidenceRef() },
        .{ .role = .elaboration_effect_row, .ref = effect_row.evidenceRef() },
    };
    const dependency_refs = [_]Evidence.Ref{
        closure_certificate_ref,
        source_map.evidenceRef(),
        effect_row.evidenceRef(),
    };
    const certificate = Elaboration.Certificate.init(.{
        .elaborated_program_label = "strict-elaboration",
        .source_program_ref = source_ref,
        .residual_program_ref = residual_ref,
        .closure_certificate_ref = closure_certificate_ref,
        .closure_graph_ref = closure_graph_ref,
        .closure_report_ref = closure_report_ref,
        .source_map_ref = source_map.evidenceRef(),
        .effect_row_ref = effect_row.evidenceRef(),
        .trace_map_ref = trace_map.evidenceRef(),
        .normal_form_ref = normal_form.evidenceRef(),
        .policy = policy,
        .normal_form = .strict_closed,
        .selected_static_treaty_plan_refs = &.{static_plan_ref},
        .summary_counts = .{
            .root_effect_shapes = 1,
            .internal_routes_elaborated = 1,
        },
        .evidence_dependency_refs = dependency_refs[0..],
        .dependencies = dependencies[0..],
    });

    try certificate.check(policy, closure_graph_ref, closure_report_ref, closure_certificate_ref, source_map, effect_row, trace_map, normal_form, static_plans[0..], &.{});
    const foreign_ref = Evidence.refFor(Evidence.domains.program_plan, 0xE1A817, .{ .label = "foreign" });
    const foreign_shape = Closure.EffectShape.init(.{
        .program_label = "foreign",
        .plan_hash = foreign_ref.fingerprint,
        .kind = .operation,
        .site_index = 1,
        .protocol_label = "foreign",
    });
    const foreign_plan = Closure.StaticTreatyPlan.init(.{
        .label = "foreign.plan",
        .source_shape = foreign_shape,
        .selected_semantic_body = .declarative,
        .dependencies = static_plan_dependencies[0..],
    });
    const mixed_source_entries = [_]Elaboration.SourceMap.Entry{
        source_map_entries[0],
        .{
            .source_ref = foreign_shape.evidenceRef(),
            .residual_ref = residual_ref,
            .source_site_index = 1,
            .static_treaty_plan_ref = foreign_plan.evidenceRef(),
            .disposition = .preserved,
            .label = "foreign",
        },
    };
    const mixed_source_map = Elaboration.SourceMap.init("mixed-source-elaboration-map", mixed_source_entries[0..], &.{});
    const mixed_trace_entries = [_]Elaboration.TraceMap.Entry{
        trace_entries[0],
        .{ .source_ref = foreign_shape.evidenceRef(), .residual_ref = residual_ref, .trace_label = "foreign" },
    };
    const mixed_trace = Elaboration.TraceMap.init("mixed-source-elaboration-trace", mixed_trace_entries[0..]);
    const mixed_effect_row = Elaboration.EffectRow.init(.{
        .label = "mixed-source-elaboration-row",
        .source_program_ref = source_ref,
        .residual_program_ref = residual_ref,
        .normal_form = .strict_closed,
        .source_effect_shapes = 2,
        .closed_effect_shapes = 2,
    });
    const mixed_normal_form = Elaboration.NormalForm.init("mixed-source-elaboration-normal-form", .strict_closed, closure_certificate_ref, mixed_effect_row.evidenceRef(), 0);
    const mixed_static_plan_refs = [_]Evidence.Ref{ static_plan_ref, foreign_plan.evidenceRef() };
    const mixed_source_certificate = Elaboration.Certificate.init(.{
        .elaborated_program_label = "mixed-source-elaboration",
        .source_program_ref = source_ref,
        .residual_program_ref = residual_ref,
        .closure_certificate_ref = closure_certificate_ref,
        .closure_graph_ref = closure_graph_ref,
        .closure_report_ref = closure_report_ref,
        .source_map_ref = mixed_source_map.evidenceRef(),
        .effect_row_ref = mixed_effect_row.evidenceRef(),
        .trace_map_ref = mixed_trace.evidenceRef(),
        .normal_form_ref = mixed_normal_form.evidenceRef(),
        .policy = policy,
        .normal_form = .strict_closed,
        .selected_static_treaty_plan_refs = mixed_static_plan_refs[0..],
        .summary_counts = .{
            .root_effect_shapes = 2,
            .internal_routes_elaborated = 2,
        },
        .dependencies = dependencies[0..],
    });
    const mixed_static_plans = [_]Closure.StaticTreatyPlan{ static_plan, foreign_plan };
    try std.testing.expectEqual(
        error.BoundaryElaborationCertificateMismatch,
        mixed_source_certificate.check(policy, closure_graph_ref, closure_report_ref, closure_certificate_ref, mixed_source_map, mixed_effect_row, mixed_trace, mixed_normal_form, mixed_static_plans[0..], &.{}),
    );
    const forged_attribution_row = Elaboration.EffectRow.init(.{
        .label = "strict-elaboration-forged-attribution-row",
        .source_program_ref = residual_ref,
        .residual_program_ref = residual_ref,
        .normal_form = .strict_closed,
        .source_effect_shapes = 1,
        .closed_effect_shapes = 1,
    });
    const forged_attribution_normal = Elaboration.NormalForm.init("strict-elaboration-forged-attribution-normal-form", .strict_closed, closure_certificate_ref, forged_attribution_row.evidenceRef(), 0);
    const forged_attribution_certificate = Elaboration.Certificate.init(.{
        .elaborated_program_label = "strict-elaboration",
        .source_program_ref = residual_ref,
        .residual_program_ref = residual_ref,
        .closure_certificate_ref = closure_certificate_ref,
        .closure_graph_ref = closure_graph_ref,
        .closure_report_ref = closure_report_ref,
        .source_map_ref = source_map.evidenceRef(),
        .effect_row_ref = forged_attribution_row.evidenceRef(),
        .trace_map_ref = trace_map.evidenceRef(),
        .normal_form_ref = forged_attribution_normal.evidenceRef(),
        .policy = policy,
        .normal_form = .strict_closed,
        .selected_static_treaty_plan_refs = &.{static_plan_ref},
        .summary_counts = .{
            .root_effect_shapes = 1,
            .internal_routes_elaborated = 1,
        },
        .evidence_dependency_refs = dependency_refs[0..],
        .dependencies = dependencies[0..],
    });
    try std.testing.expectEqual(
        error.BoundaryElaborationCertificateMismatch,
        forged_attribution_certificate.check(policy, closure_graph_ref, closure_report_ref, closure_certificate_ref, source_map, forged_attribution_row, trace_map, forged_attribution_normal, static_plans[0..], &.{}),
    );
    var no_trace_policy = policy;
    no_trace_policy.emit_trace_map = false;
    const no_trace_certificate = Elaboration.Certificate.init(.{
        .elaborated_program_label = "strict-elaboration",
        .source_program_ref = source_ref,
        .residual_program_ref = residual_ref,
        .closure_certificate_ref = closure_certificate_ref,
        .closure_graph_ref = closure_graph_ref,
        .closure_report_ref = closure_report_ref,
        .source_map_ref = source_map.evidenceRef(),
        .effect_row_ref = effect_row.evidenceRef(),
        .normal_form_ref = normal_form.evidenceRef(),
        .policy = no_trace_policy,
        .normal_form = .strict_closed,
        .selected_static_treaty_plan_refs = &.{static_plan_ref},
        .summary_counts = .{
            .root_effect_shapes = 1,
            .internal_routes_elaborated = 1,
        },
        .evidence_dependency_refs = dependency_refs[0..],
        .dependencies = dependencies[0..],
    });
    try no_trace_certificate.check(no_trace_policy, closure_graph_ref, closure_report_ref, closure_certificate_ref, source_map, effect_row, null, normal_form, static_plans[0..], &.{});
    const forbidden_trace_certificate = Elaboration.Certificate.init(.{
        .elaborated_program_label = "strict-elaboration",
        .source_program_ref = source_ref,
        .residual_program_ref = residual_ref,
        .closure_certificate_ref = closure_certificate_ref,
        .closure_graph_ref = closure_graph_ref,
        .closure_report_ref = closure_report_ref,
        .source_map_ref = source_map.evidenceRef(),
        .effect_row_ref = effect_row.evidenceRef(),
        .trace_map_ref = trace_map.evidenceRef(),
        .normal_form_ref = normal_form.evidenceRef(),
        .policy = no_trace_policy,
        .normal_form = .strict_closed,
        .selected_static_treaty_plan_refs = &.{static_plan_ref},
        .summary_counts = .{
            .root_effect_shapes = 1,
            .internal_routes_elaborated = 1,
        },
        .evidence_dependency_refs = dependency_refs[0..],
        .dependencies = dependencies[0..],
    });
    try std.testing.expectEqual(
        error.BoundaryElaborationCertificateMismatch,
        forbidden_trace_certificate.check(no_trace_policy, closure_graph_ref, closure_report_ref, closure_certificate_ref, source_map, effect_row, trace_map, normal_form, static_plans[0..], &.{}),
    );
    const forged_label_trace_entries = [_]Elaboration.TraceMap.Entry{.{ .source_ref = source_shape_ref, .residual_ref = residual_ref, .trace_label = "forged-root" }};
    const forged_label_trace = Elaboration.TraceMap.init("strict-elaboration-forged-label-trace", forged_label_trace_entries[0..]);
    const forged_label_certificate = Elaboration.Certificate.init(.{
        .elaborated_program_label = "strict-elaboration",
        .source_program_ref = source_ref,
        .residual_program_ref = residual_ref,
        .closure_certificate_ref = closure_certificate_ref,
        .closure_graph_ref = closure_graph_ref,
        .closure_report_ref = closure_report_ref,
        .source_map_ref = source_map.evidenceRef(),
        .effect_row_ref = effect_row.evidenceRef(),
        .trace_map_ref = forged_label_trace.evidenceRef(),
        .normal_form_ref = normal_form.evidenceRef(),
        .policy = policy,
        .normal_form = .strict_closed,
        .selected_static_treaty_plan_refs = &.{static_plan_ref},
        .summary_counts = .{
            .root_effect_shapes = 1,
            .internal_routes_elaborated = 1,
        },
        .evidence_dependency_refs = dependency_refs[0..],
        .dependencies = dependencies[0..],
    });
    try std.testing.expectEqual(
        error.BoundaryElaborationCertificateMismatch,
        forged_label_certificate.check(policy, closure_graph_ref, closure_report_ref, closure_certificate_ref, source_map, effect_row, forged_label_trace, normal_form, static_plans[0..], &.{}),
    );
    const provider_route_ref = Evidence.refFor(Evidence.domains.provider_manifest, 0xE1A814, .{ .label = "unbound-certificate-provider" });
    const provider_program_ref = Evidence.refFor(Evidence.domains.program_plan, 0xE1A815, .{ .label = "unbound-certificate-provider-program" });
    const provider_plan = Closure.StaticTreatyPlan.init(.{
        .label = "unbound-certificate-provider-plan",
        .source_shape = source_shape,
        .selected_provider_ref = provider_route_ref,
        .selected_provider_offer_ref = provider_route_ref,
        .selected_capability_ref = provider_route_ref,
        .selected_semantic_body = .boundary_program,
        .selected_provider_program_ref = provider_program_ref,
        .selected_provider_program_mapping_fingerprint = 0xE1A816,
        .selected_provider_program_request_mapping_tag = "payload_to_args",
        .selected_provider_program_result_mapping_tag = "result_to_resume",
        .selected_provider_program_effect_shape_count = 0,
        .selected_provider_program_effect_shape_fingerprint = Evidence.fingerprintBoundaryEffectShapeSet(&.{}),
    });
    const forged_support_plan = Closure.StaticTreatyPlan.init(.{
        .label = "forged-support-certificate-provider-plan",
        .source_shape = source_shape,
        .selected_provider_ref = provider_route_ref,
        .selected_provider_offer_ref = provider_route_ref,
        .selected_capability_ref = provider_route_ref,
        .selected_semantic_body = .boundary_program,
        .selected_provider_program_ref = provider_program_ref,
        .selected_provider_program_mapping_fingerprint = 0xE1A816,
        .selected_provider_program_request_mapping_tag = "payload_to_args",
        .selected_provider_program_result_mapping_tag = "result_to_resume",
        .selected_provider_program_mapping_support_fingerprint = 0xE1A817,
        .selected_provider_program_effect_shape_count = 0,
        .selected_provider_program_effect_shape_fingerprint = Evidence.fingerprintBoundaryEffectShapeSet(&.{}),
    });
    const provider_source_map_entries = [_]Elaboration.SourceMap.Entry{.{
        .source_ref = source_shape_ref,
        .residual_ref = residual_ref,
        .source_site_index = 0,
        .provider_program_ref = provider_program_ref,
        .static_treaty_plan_ref = provider_plan.evidenceRef(),
        .disposition = .provider_program_linked,
        .label = "unbound-certificate-provider",
    }};
    const provider_source_map = Elaboration.SourceMap.init("unbound-certificate-provider-map", provider_source_map_entries[0..], &.{});
    const provider_trace_entries = [_]Elaboration.TraceMap.Entry{.{ .source_ref = source_shape_ref, .residual_ref = residual_ref, .trace_label = "unbound-certificate-provider" }};
    const provider_trace = Elaboration.TraceMap.init("unbound-certificate-provider-trace", provider_trace_entries[0..]);
    const provider_row = Elaboration.EffectRow.init(.{
        .label = "unbound-certificate-provider-row",
        .source_program_ref = source_ref,
        .residual_program_ref = residual_ref,
        .normal_form = .strict_closed,
        .source_effect_shapes = 1,
        .closed_effect_shapes = 1,
        .provider_program_links = 1,
    });
    const provider_normal = Elaboration.NormalForm.init("unbound-certificate-provider-normal", .strict_closed, closure_certificate_ref, provider_row.evidenceRef(), 0);
    const provider_dependencies = [_]Evidence.Dependency{
        .{ .role = .closure_certificate, .ref = closure_certificate_ref },
        .{ .role = .residual_program, .ref = residual_ref },
        .{ .role = .elaboration_source_map, .ref = provider_source_map.evidenceRef() },
        .{ .role = .elaboration_effect_row, .ref = provider_row.evidenceRef() },
        .{ .role = .elaboration_trace_map, .ref = provider_trace.evidenceRef() },
        .{ .role = .normal_form, .ref = provider_normal.evidenceRef() },
    };
    const provider_certificate = Elaboration.Certificate.init(.{
        .elaborated_program_label = "unbound-certificate-provider",
        .source_program_ref = source_ref,
        .residual_program_ref = residual_ref,
        .closure_certificate_ref = closure_certificate_ref,
        .closure_graph_ref = closure_graph_ref,
        .closure_report_ref = closure_report_ref,
        .source_map_ref = provider_source_map.evidenceRef(),
        .effect_row_ref = provider_row.evidenceRef(),
        .trace_map_ref = provider_trace.evidenceRef(),
        .normal_form_ref = provider_normal.evidenceRef(),
        .policy = policy,
        .normal_form = .strict_closed,
        .selected_static_treaty_plan_refs = &.{provider_plan.evidenceRef()},
        .inlined_provider_program_refs = &.{provider_program_ref},
        .summary_counts = .{
            .root_effect_shapes = 1,
            .internal_routes_elaborated = 1,
            .provider_programs_linked = 1,
        },
        .dependencies = provider_dependencies[0..],
    });
    try std.testing.expectEqual(
        error.BoundaryElaborationCertificateMismatch,
        provider_certificate.check(policy, closure_graph_ref, closure_report_ref, closure_certificate_ref, provider_source_map, provider_row, provider_trace, provider_normal, &.{provider_plan}, &.{}),
    );
    const forged_support_map_entries = [_]Elaboration.SourceMap.Entry{.{
        .source_ref = source_shape_ref,
        .residual_ref = source_ref,
        .source_site_index = 0,
        .provider_program_ref = provider_program_ref,
        .static_treaty_plan_ref = forged_support_plan.evidenceRef(),
        .disposition = .provider_program_linked,
        .label = "forged-support-provider",
    }};
    const forged_support_map = Elaboration.SourceMap.init("forged-support-provider-map", forged_support_map_entries[0..], &.{});
    const forged_support_trace = Elaboration.TraceMap.init("forged-support-provider-trace", &.{.{ .source_ref = source_shape_ref, .residual_ref = source_ref, .trace_label = "forged-support-provider" }});
    const forged_support_row = Elaboration.EffectRow.init(.{
        .label = "forged-support-provider-row",
        .source_program_ref = source_ref,
        .residual_program_ref = source_ref,
        .normal_form = .strict_closed,
        .source_effect_shapes = 1,
        .closed_effect_shapes = 1,
        .provider_program_links = 1,
    });
    const forged_support_normal = Elaboration.NormalForm.init("forged-support-provider-normal", .strict_closed, closure_certificate_ref, forged_support_row.evidenceRef(), 0);
    const forged_support_dependencies = [_]Evidence.Dependency{
        .{ .role = .closure_certificate, .ref = closure_certificate_ref },
        .{ .role = .residual_program, .ref = source_ref },
        .{ .role = .elaboration_source_map, .ref = forged_support_map.evidenceRef() },
        .{ .role = .elaboration_effect_row, .ref = forged_support_row.evidenceRef() },
        .{ .role = .elaboration_trace_map, .ref = forged_support_trace.evidenceRef() },
        .{ .role = .normal_form, .ref = forged_support_normal.evidenceRef() },
    };
    const forged_support_certificate = Elaboration.Certificate.init(.{
        .elaborated_program_label = "forged-support-provider",
        .source_program_ref = source_ref,
        .residual_program_ref = source_ref,
        .closure_certificate_ref = closure_certificate_ref,
        .closure_graph_ref = closure_graph_ref,
        .closure_report_ref = closure_report_ref,
        .source_map_ref = forged_support_map.evidenceRef(),
        .effect_row_ref = forged_support_row.evidenceRef(),
        .trace_map_ref = forged_support_trace.evidenceRef(),
        .normal_form_ref = forged_support_normal.evidenceRef(),
        .policy = policy,
        .normal_form = .strict_closed,
        .selected_static_treaty_plan_refs = &.{forged_support_plan.evidenceRef()},
        .inlined_provider_program_refs = &.{provider_program_ref},
        .summary_counts = .{
            .root_effect_shapes = 1,
            .internal_routes_elaborated = 1,
            .provider_programs_linked = 1,
        },
        .dependencies = forged_support_dependencies[0..],
    });
    try std.testing.expectEqual(
        error.BoundaryElaborationCertificateMismatch,
        forged_support_certificate.check(policy, closure_graph_ref, closure_report_ref, closure_certificate_ref, forged_support_map, forged_support_row, forged_support_trace, forged_support_normal, &.{forged_support_plan}, &.{}),
    );
    var forged_alias_row = effect_row;
    forged_alias_row.strict_closed = false;
    forged_alias_row.fingerprint = forged_alias_row.computeFingerprint();
    const forged_alias_normal = Elaboration.NormalForm.init("strict-elaboration-forged-alias-normal-form", .strict_closed, closure_certificate_ref, forged_alias_row.evidenceRef(), 0);
    const forged_alias_dependencies = [_]Evidence.Dependency{
        .{ .role = .closure_certificate, .ref = closure_certificate_ref },
        .{ .role = .elaboration_source_map, .ref = source_map.evidenceRef() },
        .{ .role = .elaboration_effect_row, .ref = forged_alias_row.evidenceRef() },
    };
    const forged_alias_dependency_refs = [_]Evidence.Ref{
        closure_certificate_ref,
        source_map.evidenceRef(),
        forged_alias_row.evidenceRef(),
    };
    const forged_alias_certificate = Elaboration.Certificate.init(.{
        .elaborated_program_label = "strict-elaboration",
        .source_program_ref = source_ref,
        .residual_program_ref = residual_ref,
        .closure_certificate_ref = closure_certificate_ref,
        .closure_graph_ref = closure_graph_ref,
        .closure_report_ref = closure_report_ref,
        .source_map_ref = source_map.evidenceRef(),
        .effect_row_ref = forged_alias_row.evidenceRef(),
        .trace_map_ref = trace_map.evidenceRef(),
        .normal_form_ref = forged_alias_normal.evidenceRef(),
        .policy = policy,
        .normal_form = .strict_closed,
        .selected_static_treaty_plan_refs = &.{static_plan_ref},
        .summary_counts = .{
            .root_effect_shapes = 1,
            .internal_routes_elaborated = 1,
        },
        .evidence_dependency_refs = forged_alias_dependency_refs[0..],
        .dependencies = forged_alias_dependencies[0..],
    });
    try std.testing.expectEqual(
        error.BoundaryElaborationCertificateMismatch,
        forged_alias_certificate.check(policy, closure_graph_ref, closure_report_ref, closure_certificate_ref, source_map, forged_alias_row, trace_map, forged_alias_normal, static_plans[0..], &.{}),
    );
    const forged_blocked_entries = [_]Elaboration.SourceMap.Entry{.{
        .source_ref = source_shape_ref,
        .residual_ref = residual_ref,
        .source_site_index = 0,
        .static_treaty_plan_ref = static_plan_ref,
        .disposition = .blocked,
        .label = "forged-blocked-route",
    }};
    const forged_blocked_map = Elaboration.SourceMap.init("forged-blocked-route-map", forged_blocked_entries[0..], &.{});
    const forged_blocked_trace = Elaboration.TraceMap.init("forged-blocked-route-trace", trace_entries[0..]);
    const forged_blocked_row = Elaboration.EffectRow.init(.{
        .label = "forged-blocked-route-row",
        .source_program_ref = source_ref,
        .residual_program_ref = residual_ref,
        .normal_form = .partial_with_blockers,
        .source_effect_shapes = 1,
        .unsupported_shapes = 1,
        .blockers = 1,
    });
    const forged_blocked_normal = Elaboration.NormalForm.init("forged-blocked-route-normal", .partial_with_blockers, closure_certificate_ref, forged_blocked_row.evidenceRef(), 1);
    const forged_blocker_ref = Evidence.refFor(Evidence.domains.boundary_closure_report, 0xE1A813, .{ .kind_tag = "forged_blocker" });
    const forged_blocked_cert = Elaboration.Certificate.init(.{
        .elaborated_program_label = "forged-blocked-route",
        .source_program_ref = source_ref,
        .residual_program_ref = residual_ref,
        .closure_certificate_ref = closure_certificate_ref,
        .closure_graph_ref = closure_graph_ref,
        .closure_report_ref = closure_report_ref,
        .source_map_ref = forged_blocked_map.evidenceRef(),
        .effect_row_ref = forged_blocked_row.evidenceRef(),
        .trace_map_ref = forged_blocked_trace.evidenceRef(),
        .normal_form_ref = forged_blocked_normal.evidenceRef(),
        .policy = Elaboration.Policy.auditOnly(),
        .normal_form = .partial_with_blockers,
        .selected_static_treaty_plan_refs = &.{static_plan_ref},
        .blocker_refs = &.{forged_blocker_ref},
        .summary_counts = .{
            .root_effect_shapes = 1,
            .blockers = 1,
        },
        .dependencies = dependencies[0..],
    });
    try std.testing.expectEqual(
        error.BoundaryElaborationCertificateMismatch,
        forged_blocked_cert.check(Elaboration.Policy.auditOnly(), closure_graph_ref, closure_report_ref, closure_certificate_ref, forged_blocked_map, forged_blocked_row, forged_blocked_trace, forged_blocked_normal, static_plans[0..], &.{}),
    );
    const direct_blocker = Evidence.boundaryClosureBlocker(.{
        .tag = .unsupported_shape_planning,
        .subject = source_shape_ref,
        .summary = "direct blocker identity",
    });
    const direct_blocker_ref = Evidence.refForBoundaryClosureBlocker(direct_blocker);
    const direct_blocked_entries = [_]Elaboration.SourceMap.Entry{.{
        .source_ref = source_shape_ref,
        .residual_ref = residual_ref,
        .source_site_index = 0,
        .blocker_ref = direct_blocker_ref,
        .disposition = .blocked,
        .label = "direct-blocked-route",
    }};
    const direct_blocked_map = Elaboration.SourceMap.init("direct-blocked-route-map", direct_blocked_entries[0..], &.{});
    const direct_blocked_trace = Elaboration.TraceMap.init("direct-blocked-route-trace", &.{.{ .source_ref = source_shape_ref, .residual_ref = residual_ref, .trace_label = "direct-blocked-route" }});
    const direct_blocked_row = Elaboration.EffectRow.init(.{
        .label = "direct-blocked-route-row",
        .source_program_ref = source_ref,
        .residual_program_ref = residual_ref,
        .normal_form = .partial_with_blockers,
        .source_effect_shapes = 1,
        .unsupported_shapes = 1,
        .blockers = 1,
    });
    const direct_blocked_normal = Elaboration.NormalForm.init("direct-blocked-route-normal", .partial_with_blockers, closure_certificate_ref, direct_blocked_row.evidenceRef(), 1);
    const direct_blocked_cert = Elaboration.Certificate.init(.{
        .elaborated_program_label = "direct-blocked-route",
        .source_program_ref = source_ref,
        .residual_program_ref = residual_ref,
        .closure_certificate_ref = closure_certificate_ref,
        .closure_graph_ref = closure_graph_ref,
        .closure_report_ref = closure_report_ref,
        .source_map_ref = direct_blocked_map.evidenceRef(),
        .effect_row_ref = direct_blocked_row.evidenceRef(),
        .trace_map_ref = direct_blocked_trace.evidenceRef(),
        .normal_form_ref = direct_blocked_normal.evidenceRef(),
        .policy = Elaboration.Policy.auditOnly(),
        .normal_form = .partial_with_blockers,
        .blocker_refs = &.{direct_blocker_ref},
        .summary_counts = .{
            .root_effect_shapes = 1,
            .blockers = 1,
        },
    });
    try direct_blocked_cert.check(Elaboration.Policy.auditOnly(), closure_graph_ref, closure_report_ref, closure_certificate_ref, direct_blocked_map, direct_blocked_row, direct_blocked_trace, direct_blocked_normal, &.{}, &.{});
    const inflated_unsupported_row = Elaboration.EffectRow.init(.{
        .label = "inflated-unsupported-route-row",
        .source_program_ref = source_ref,
        .residual_program_ref = residual_ref,
        .normal_form = .partial_with_blockers,
        .source_effect_shapes = 1,
        .unsupported_shapes = 2,
        .blockers = 1,
    });
    const inflated_unsupported_normal = Elaboration.NormalForm.init("inflated-unsupported-route-normal", .partial_with_blockers, closure_certificate_ref, inflated_unsupported_row.evidenceRef(), 1);
    const inflated_unsupported_cert = Elaboration.Certificate.init(.{
        .elaborated_program_label = "inflated-unsupported-route",
        .source_program_ref = source_ref,
        .residual_program_ref = residual_ref,
        .closure_certificate_ref = closure_certificate_ref,
        .closure_graph_ref = closure_graph_ref,
        .closure_report_ref = closure_report_ref,
        .source_map_ref = direct_blocked_map.evidenceRef(),
        .effect_row_ref = inflated_unsupported_row.evidenceRef(),
        .trace_map_ref = direct_blocked_trace.evidenceRef(),
        .normal_form_ref = inflated_unsupported_normal.evidenceRef(),
        .policy = Elaboration.Policy.auditOnly(),
        .normal_form = .partial_with_blockers,
        .blocker_refs = &.{direct_blocker_ref},
        .summary_counts = .{
            .root_effect_shapes = 1,
            .blockers = 1,
        },
    });
    try std.testing.expectEqual(
        error.BoundaryElaborationCertificateMismatch,
        inflated_unsupported_cert.check(Elaboration.Policy.auditOnly(), closure_graph_ref, closure_report_ref, closure_certificate_ref, direct_blocked_map, inflated_unsupported_row, direct_blocked_trace, inflated_unsupported_normal, &.{}, &.{}),
    );
    var fail_closed_partial_policy = Elaboration.Policy.strictStatic();
    fail_closed_partial_policy.allow_partial_with_blockers = true;
    fail_closed_partial_policy.max_blockers = 1;
    const fail_closed_blocked_cert = Elaboration.Certificate.init(.{
        .elaborated_program_label = "direct-blocked-route",
        .source_program_ref = source_ref,
        .residual_program_ref = residual_ref,
        .closure_certificate_ref = closure_certificate_ref,
        .closure_graph_ref = closure_graph_ref,
        .closure_report_ref = closure_report_ref,
        .source_map_ref = direct_blocked_map.evidenceRef(),
        .effect_row_ref = direct_blocked_row.evidenceRef(),
        .trace_map_ref = direct_blocked_trace.evidenceRef(),
        .normal_form_ref = direct_blocked_normal.evidenceRef(),
        .policy = fail_closed_partial_policy,
        .normal_form = .partial_with_blockers,
        .blocker_refs = &.{direct_blocker_ref},
        .summary_counts = .{
            .root_effect_shapes = 1,
            .blockers = 1,
        },
    });
    try std.testing.expectEqual(
        error.BoundaryElaborationBlocked,
        fail_closed_blocked_cert.check(fail_closed_partial_policy, closure_graph_ref, closure_report_ref, closure_certificate_ref, direct_blocked_map, direct_blocked_row, direct_blocked_trace, direct_blocked_normal, &.{}, &.{}),
    );
    const forged_direct_blocked_cert = Elaboration.Certificate.init(.{
        .elaborated_program_label = "direct-blocked-route",
        .source_program_ref = source_ref,
        .residual_program_ref = residual_ref,
        .closure_certificate_ref = closure_certificate_ref,
        .closure_graph_ref = closure_graph_ref,
        .closure_report_ref = closure_report_ref,
        .source_map_ref = direct_blocked_map.evidenceRef(),
        .effect_row_ref = direct_blocked_row.evidenceRef(),
        .trace_map_ref = direct_blocked_trace.evidenceRef(),
        .normal_form_ref = direct_blocked_normal.evidenceRef(),
        .policy = Elaboration.Policy.auditOnly(),
        .normal_form = .partial_with_blockers,
        .blocker_refs = &.{forged_blocker_ref},
        .summary_counts = .{
            .root_effect_shapes = 1,
            .blockers = 1,
        },
    });
    try std.testing.expectEqual(
        error.BoundaryElaborationCertificateMismatch,
        forged_direct_blocked_cert.check(Elaboration.Policy.auditOnly(), closure_graph_ref, closure_report_ref, closure_certificate_ref, direct_blocked_map, direct_blocked_row, direct_blocked_trace, direct_blocked_normal, &.{}, &.{}),
    );
    const forged_unblocked_blocker_row = Elaboration.EffectRow.init(.{
        .label = "forged-unblocked-blocker-row",
        .source_program_ref = source_ref,
        .residual_program_ref = residual_ref,
        .normal_form = .partial_with_blockers,
        .source_effect_shapes = 1,
        .closed_effect_shapes = 1,
        .blockers = 1,
    });
    const forged_unblocked_blocker_normal = Elaboration.NormalForm.init("forged-unblocked-blocker-normal", .partial_with_blockers, closure_certificate_ref, forged_unblocked_blocker_row.evidenceRef(), 1);
    const forged_unblocked_blocker_cert = Elaboration.Certificate.init(.{
        .elaborated_program_label = "forged-unblocked-blocker",
        .source_program_ref = source_ref,
        .residual_program_ref = residual_ref,
        .closure_certificate_ref = closure_certificate_ref,
        .closure_graph_ref = closure_graph_ref,
        .closure_report_ref = closure_report_ref,
        .source_map_ref = source_map.evidenceRef(),
        .effect_row_ref = forged_unblocked_blocker_row.evidenceRef(),
        .trace_map_ref = trace_map.evidenceRef(),
        .normal_form_ref = forged_unblocked_blocker_normal.evidenceRef(),
        .policy = Elaboration.Policy.auditOnly(),
        .normal_form = .partial_with_blockers,
        .selected_static_treaty_plan_refs = &.{static_plan_ref},
        .blocker_refs = &.{forged_blocker_ref},
        .summary_counts = .{
            .root_effect_shapes = 1,
            .internal_routes_elaborated = 1,
            .blockers = 1,
        },
        .dependencies = dependencies[0..],
    });
    try std.testing.expectEqual(
        error.BoundaryElaborationCertificateMismatch,
        forged_unblocked_blocker_cert.check(Elaboration.Policy.auditOnly(), closure_graph_ref, closure_report_ref, closure_certificate_ref, source_map, forged_unblocked_blocker_row, trace_map, forged_unblocked_blocker_normal, static_plans[0..], &.{}),
    );
    var forged_policy_summary_certificate = certificate;
    forged_policy_summary_certificate.policy_summary.policy_label = "forged-policy-label";
    try std.testing.expectEqual(
        error.BoundaryElaborationPolicyMismatch,
        forged_policy_summary_certificate.check(policy, closure_graph_ref, closure_report_ref, closure_certificate_ref, source_map, effect_row, trace_map, normal_form, static_plans[0..], &.{}),
    );
    const non_program_residual_entries = [_]Elaboration.SourceMap.Entry{.{
        .source_ref = source_shape_ref,
        .residual_ref = closure_graph_ref,
        .source_site_index = 0,
        .residual_site_index = 0,
        .static_treaty_plan_ref = static_plan_ref,
        .disposition = .preserved,
        .label = "non-program-residual",
    }};
    const non_program_residual_map = Elaboration.SourceMap.init("non-program-residual-map", non_program_residual_entries[0..], &.{});
    const non_program_residual_trace = Elaboration.TraceMap.init("non-program-residual-trace", &.{.{ .source_ref = source_shape_ref, .residual_ref = closure_graph_ref, .trace_label = "non-program-residual" }});
    const non_program_residual_row = Elaboration.EffectRow.init(.{
        .label = "non-program-residual-row",
        .source_program_ref = source_ref,
        .residual_program_ref = closure_graph_ref,
        .normal_form = .strict_closed,
        .source_effect_shapes = 1,
        .closed_effect_shapes = 1,
    });
    const non_program_residual_normal = Elaboration.NormalForm.init("non-program-residual-normal", .strict_closed, closure_certificate_ref, non_program_residual_row.evidenceRef(), 0);
    const non_program_residual_certificate = Elaboration.Certificate.init(.{
        .elaborated_program_label = "non-program-residual",
        .source_program_ref = source_ref,
        .residual_program_ref = closure_graph_ref,
        .closure_certificate_ref = closure_certificate_ref,
        .closure_graph_ref = closure_graph_ref,
        .closure_report_ref = closure_report_ref,
        .source_map_ref = non_program_residual_map.evidenceRef(),
        .effect_row_ref = non_program_residual_row.evidenceRef(),
        .trace_map_ref = non_program_residual_trace.evidenceRef(),
        .normal_form_ref = non_program_residual_normal.evidenceRef(),
        .policy = policy,
        .normal_form = .strict_closed,
        .selected_static_treaty_plan_refs = &.{static_plan_ref},
        .summary_counts = .{
            .root_effect_shapes = 1,
            .internal_routes_elaborated = 1,
        },
    });
    try std.testing.expectEqual(
        error.BoundaryElaborationCertificateMismatch,
        non_program_residual_certificate.check(policy, closure_graph_ref, closure_report_ref, closure_certificate_ref, non_program_residual_map, non_program_residual_row, non_program_residual_trace, non_program_residual_normal, static_plans[0..], &.{}),
    );
    const wrong_residual_ref = Evidence.refFor(Evidence.domains.program_plan, 0xE1A812, .{ .label = "wrong-residual" });
    const wrong_residual_entries = [_]Elaboration.SourceMap.Entry{.{
        .source_ref = source_ref,
        .residual_ref = wrong_residual_ref,
        .source_site_index = 0,
        .residual_site_index = 0,
        .disposition = .preserved,
        .label = "wrong-residual",
    }};
    const wrong_residual_source_map = Elaboration.SourceMap.init("strict-elaboration-wrong-residual-map", wrong_residual_entries[0..], &.{});
    const wrong_residual_trace_entries = [_]Elaboration.TraceMap.Entry{.{ .source_ref = source_ref, .residual_ref = wrong_residual_ref, .trace_label = "wrong-residual" }};
    const wrong_residual_trace_map = Elaboration.TraceMap.init("strict-elaboration-wrong-residual-trace", wrong_residual_trace_entries[0..]);
    const wrong_residual_certificate = Elaboration.Certificate.init(.{
        .elaborated_program_label = "strict-elaboration",
        .source_program_ref = source_ref,
        .residual_program_ref = residual_ref,
        .closure_certificate_ref = closure_certificate_ref,
        .closure_graph_ref = closure_graph_ref,
        .closure_report_ref = closure_report_ref,
        .source_map_ref = wrong_residual_source_map.evidenceRef(),
        .effect_row_ref = effect_row.evidenceRef(),
        .trace_map_ref = wrong_residual_trace_map.evidenceRef(),
        .normal_form_ref = normal_form.evidenceRef(),
        .policy = policy,
        .normal_form = .strict_closed,
        .summary_counts = .{
            .root_effect_shapes = 1,
            .internal_routes_elaborated = 1,
        },
    });
    try std.testing.expectEqual(
        error.BoundaryElaborationCertificateMismatch,
        wrong_residual_certificate.check(policy, closure_graph_ref, closure_report_ref, closure_certificate_ref, wrong_residual_source_map, effect_row, wrong_residual_trace_map, normal_form, &.{}, &.{}),
    );
    const missing_residual_entries = [_]Elaboration.SourceMap.Entry{.{
        .source_ref = source_ref,
        .source_site_index = 0,
        .residual_site_index = 0,
        .disposition = .preserved,
        .label = "missing-residual",
    }};
    const missing_residual_source_map = Elaboration.SourceMap.init("strict-elaboration-missing-residual-map", missing_residual_entries[0..], &.{});
    const missing_residual_trace_entries = [_]Elaboration.TraceMap.Entry{.{ .source_ref = source_ref, .residual_ref = source_ref, .trace_label = "missing-residual" }};
    const missing_residual_trace_map = Elaboration.TraceMap.init("strict-elaboration-missing-residual-trace", missing_residual_trace_entries[0..]);
    const missing_residual_certificate = Elaboration.Certificate.init(.{
        .elaborated_program_label = "strict-elaboration",
        .source_program_ref = source_ref,
        .residual_program_ref = residual_ref,
        .closure_certificate_ref = closure_certificate_ref,
        .closure_graph_ref = closure_graph_ref,
        .closure_report_ref = closure_report_ref,
        .source_map_ref = missing_residual_source_map.evidenceRef(),
        .effect_row_ref = effect_row.evidenceRef(),
        .trace_map_ref = missing_residual_trace_map.evidenceRef(),
        .normal_form_ref = normal_form.evidenceRef(),
        .policy = policy,
        .normal_form = .strict_closed,
        .summary_counts = .{
            .root_effect_shapes = 1,
            .internal_routes_elaborated = 1,
        },
    });
    try std.testing.expectEqual(
        error.BoundaryElaborationCertificateMismatch,
        missing_residual_certificate.check(policy, closure_graph_ref, closure_report_ref, closure_certificate_ref, missing_residual_source_map, effect_row, missing_residual_trace_map, normal_form, &.{}, &.{}),
    );
    const route_without_plan_entries = [_]Elaboration.SourceMap.Entry{.{
        .source_ref = source_ref,
        .residual_ref = residual_ref,
        .source_site_index = 0,
        .residual_site_index = 0,
        .disposition = .pipeline_adapter,
        .label = "pipeline-without-plan",
    }};
    const route_without_plan_map = Elaboration.SourceMap.init("strict-elaboration-route-without-plan-map", route_without_plan_entries[0..], &.{});
    const route_without_plan_trace = Elaboration.TraceMap.init("strict-elaboration-route-without-plan-trace", trace_entries[0..]);
    const route_without_plan_row = Elaboration.EffectRow.init(.{
        .label = "strict-elaboration-route-without-plan-row",
        .source_program_ref = source_ref,
        .residual_program_ref = residual_ref,
        .normal_form = .strict_closed,
        .source_effect_shapes = 1,
        .closed_effect_shapes = 1,
        .pipeline_routes = 1,
    });
    const route_without_plan_normal = Elaboration.NormalForm.init("strict-elaboration-route-without-plan-normal-form", .strict_closed, closure_certificate_ref, route_without_plan_row.evidenceRef(), 0);
    const route_without_plan_certificate = Elaboration.Certificate.init(.{
        .elaborated_program_label = "strict-elaboration",
        .source_program_ref = source_ref,
        .residual_program_ref = residual_ref,
        .closure_certificate_ref = closure_certificate_ref,
        .closure_graph_ref = closure_graph_ref,
        .closure_report_ref = closure_report_ref,
        .source_map_ref = route_without_plan_map.evidenceRef(),
        .effect_row_ref = route_without_plan_row.evidenceRef(),
        .trace_map_ref = route_without_plan_trace.evidenceRef(),
        .normal_form_ref = route_without_plan_normal.evidenceRef(),
        .policy = policy,
        .normal_form = .strict_closed,
        .summary_counts = .{
            .root_effect_shapes = 1,
            .internal_routes_elaborated = 1,
            .pipeline_routes_elaborated = 1,
        },
    });
    try std.testing.expectEqual(
        error.BoundaryElaborationCertificateMismatch,
        route_without_plan_certificate.check(policy, closure_graph_ref, closure_report_ref, closure_certificate_ref, route_without_plan_map, route_without_plan_row, route_without_plan_trace, route_without_plan_normal, &.{}, &.{}),
    );
    try std.testing.expectEqual(
        error.BoundaryElaborationCertificateMismatch,
        certificate.check(policy, closure_certificate_ref, closure_report_ref, closure_certificate_ref, source_map, effect_row, trace_map, normal_form, &.{}, &.{}),
    );
    try std.testing.expectEqual(
        error.BoundaryElaborationCertificateMismatch,
        certificate.check(policy, closure_graph_ref, closure_certificate_ref, closure_certificate_ref, source_map, effect_row, trace_map, normal_form, &.{}, &.{}),
    );
    try std.testing.expectEqual(
        error.BoundaryElaborationCertificateMismatch,
        certificate.check(policy, closure_graph_ref, closure_report_ref, closure_graph_ref, source_map, effect_row, trace_map, normal_form, &.{}, &.{}),
    );
    const wrong_dependency_refs = [_]Evidence.Ref{
        closure_certificate_ref,
        trace_map.evidenceRef(),
        effect_row.evidenceRef(),
    };
    const wrong_dependency_ref_certificate = Elaboration.Certificate.init(.{
        .elaborated_program_label = "strict-elaboration",
        .source_program_ref = source_ref,
        .residual_program_ref = residual_ref,
        .closure_certificate_ref = closure_certificate_ref,
        .closure_graph_ref = closure_graph_ref,
        .closure_report_ref = closure_report_ref,
        .source_map_ref = source_map.evidenceRef(),
        .effect_row_ref = effect_row.evidenceRef(),
        .trace_map_ref = trace_map.evidenceRef(),
        .normal_form_ref = normal_form.evidenceRef(),
        .policy = policy,
        .normal_form = .strict_closed,
        .summary_counts = .{
            .root_effect_shapes = 1,
            .internal_routes_elaborated = 1,
        },
        .evidence_dependency_refs = wrong_dependency_refs[0..],
        .dependencies = dependencies[0..],
    });
    try std.testing.expectEqual(
        error.BoundaryElaborationCertificateMismatch,
        wrong_dependency_ref_certificate.check(policy, closure_graph_ref, closure_report_ref, closure_certificate_ref, source_map, effect_row, trace_map, normal_form, &.{}, &.{}),
    );
    const missing_trace_certificate = Elaboration.Certificate.init(.{
        .elaborated_program_label = "strict-elaboration",
        .source_program_ref = source_ref,
        .residual_program_ref = residual_ref,
        .closure_certificate_ref = closure_certificate_ref,
        .closure_graph_ref = closure_graph_ref,
        .closure_report_ref = closure_report_ref,
        .source_map_ref = source_map.evidenceRef(),
        .effect_row_ref = effect_row.evidenceRef(),
        .normal_form_ref = normal_form.evidenceRef(),
        .policy = policy,
        .normal_form = .strict_closed,
        .dependencies = dependencies[0..],
    });
    try std.testing.expectEqual(
        error.BoundaryElaborationCertificateMismatch,
        missing_trace_certificate.check(policy, closure_graph_ref, closure_report_ref, closure_certificate_ref, source_map, effect_row, null, normal_form, &.{}, &.{}),
    );
    const tampered_entries = [_]Elaboration.SourceMap.Entry{.{
        .source_ref = closure_graph_ref,
        .residual_ref = residual_ref,
        .source_site_index = 0,
        .residual_site_index = 0,
        .disposition = .preserved,
        .label = "tampered",
    }};
    var tampered_source_map = source_map;
    tampered_source_map.entries = tampered_entries[0..];
    try std.testing.expectEqual(
        error.BoundaryElaborationCertificateMismatch,
        certificate.check(policy, closure_graph_ref, closure_report_ref, closure_certificate_ref, tampered_source_map, effect_row, trace_map, normal_form, &.{}, &.{}),
    );
    const wrong_map_fingerprint_certificate = Elaboration.Certificate.init(.{
        .elaborated_program_label = "strict-elaboration",
        .source_program_ref = source_ref,
        .residual_program_ref = residual_ref,
        .closure_certificate_ref = closure_certificate_ref,
        .closure_graph_ref = closure_graph_ref,
        .closure_report_ref = closure_report_ref,
        .source_map_ref = source_map.evidenceRef(),
        .effect_row_ref = effect_row.evidenceRef(),
        .trace_map_ref = trace_map.evidenceRef(),
        .normal_form_ref = normal_form.evidenceRef(),
        .policy = policy,
        .normal_form = .strict_closed,
        .source_to_residual_site_map_fingerprint = source_map.fingerprint + 1,
        .dependencies = dependencies[0..],
    });
    try std.testing.expectEqual(
        error.BoundaryElaborationCertificateMismatch,
        wrong_map_fingerprint_certificate.check(policy, closure_graph_ref, closure_report_ref, closure_certificate_ref, source_map, effect_row, trace_map, normal_form, &.{}, &.{}),
    );
    const wrong_reverse_map_certificate = Elaboration.Certificate.init(.{
        .elaborated_program_label = "strict-elaboration",
        .source_program_ref = source_ref,
        .residual_program_ref = residual_ref,
        .closure_certificate_ref = closure_certificate_ref,
        .closure_graph_ref = closure_graph_ref,
        .closure_report_ref = closure_report_ref,
        .source_map_ref = source_map.evidenceRef(),
        .effect_row_ref = effect_row.evidenceRef(),
        .trace_map_ref = trace_map.evidenceRef(),
        .normal_form_ref = normal_form.evidenceRef(),
        .policy = policy,
        .normal_form = .strict_closed,
        .residual_to_source_site_map_fingerprint = source_map.fingerprint + 1,
        .dependencies = dependencies[0..],
    });
    try std.testing.expectEqual(
        error.BoundaryElaborationCertificateMismatch,
        wrong_reverse_map_certificate.check(policy, closure_graph_ref, closure_report_ref, closure_certificate_ref, source_map, effect_row, trace_map, normal_form, &.{}, &.{}),
    );
    const wrong_trace_entries = [_]Elaboration.TraceMap.Entry{.{ .source_ref = source_ref, .residual_ref = closure_graph_ref, .trace_label = "wrong" }};
    const wrong_trace_map = Elaboration.TraceMap.init("strict-elaboration-wrong-trace", wrong_trace_entries[0..]);
    try std.testing.expectEqual(
        error.BoundaryElaborationCertificateMismatch,
        certificate.check(policy, closure_graph_ref, closure_report_ref, closure_certificate_ref, source_map, effect_row, wrong_trace_map, normal_form, &.{}, &.{}),
    );
    const wrong_normal_form = Elaboration.NormalForm.init("strict-elaboration-wrong-normal-form", .strict_closed, closure_graph_ref, effect_row.evidenceRef(), 0);
    try std.testing.expectEqual(
        error.BoundaryElaborationCertificateMismatch,
        certificate.check(policy, closure_graph_ref, closure_report_ref, closure_certificate_ref, source_map, effect_row, trace_map, wrong_normal_form, &.{}, &.{}),
    );
    const unclosed_effect_row = Elaboration.EffectRow.init(.{
        .label = "strict-elaboration-unclosed-row",
        .source_program_ref = source_ref,
        .residual_program_ref = residual_ref,
        .normal_form = .strict_closed,
        .source_effect_shapes = 1,
        .closed_effect_shapes = 0,
    });
    const unclosed_normal_form = Elaboration.NormalForm.init("strict-elaboration-unclosed-normal-form", .strict_closed, closure_certificate_ref, unclosed_effect_row.evidenceRef(), 0);
    const unclosed_certificate = Elaboration.Certificate.init(.{
        .elaborated_program_label = "strict-elaboration",
        .source_program_ref = source_ref,
        .residual_program_ref = residual_ref,
        .closure_certificate_ref = closure_certificate_ref,
        .closure_graph_ref = closure_graph_ref,
        .closure_report_ref = closure_report_ref,
        .source_map_ref = source_map.evidenceRef(),
        .effect_row_ref = unclosed_effect_row.evidenceRef(),
        .trace_map_ref = trace_map.evidenceRef(),
        .normal_form_ref = unclosed_normal_form.evidenceRef(),
        .policy = policy,
        .normal_form = .strict_closed,
        .dependencies = dependencies[0..],
    });
    try std.testing.expectEqual(
        error.BoundaryElaborationCertificateMismatch,
        unclosed_certificate.check(policy, closure_graph_ref, closure_report_ref, closure_certificate_ref, source_map, unclosed_effect_row, trace_map, unclosed_normal_form, &.{}, &.{}),
    );
    try std.testing.expect(Evidence.refForBoundaryElaborationCertificate(certificate).eql(certificate.evidenceRef()));
    try std.testing.expect(Evidence.refForBoundaryElaborationSourceMap(source_map).eql(source_map.evidenceRef()));
    try std.testing.expect(Evidence.refForBoundaryElaborationEffectRow(effect_row).eql(effect_row.evidenceRef()));
    try std.testing.expect(Evidence.refForBoundaryElaborationTraceMap(trace_map).eql(trace_map.evidenceRef()));
    try std.testing.expect(Evidence.refForBoundaryNormalForm(normal_form).eql(normal_form.evidenceRef()));
    try std.testing.expectEqual(Evidence.domains.boundary_elaboration_certificate.id, certificate.evidenceView().domain);
    try std.testing.expectEqual(Evidence.domains.boundary_normal_form.id, normal_form.evidenceRef().domain_id);
    try std.testing.expectEqualStrings("strict_closed", normal_form.evidenceRef().kind_tag.?);

    const blocker = (Elaboration.Blocker{
        .tag = .unsupported_world_port_lowering,
        .subject = source_ref,
        .primary = closure_certificate_ref,
        .summary = "world port lowering is not supported by this elaboration policy",
    }).toEvidenceBlocker();
    try std.testing.expect(blocker.valid());
    try std.testing.expectEqual(Evidence.domains.boundary_elaboration_certificate.id, blocker.domain);
    try std.testing.expect(Evidence.refForBoundaryElaborationBlocker(blocker).kind_tag != null);

    var world_row = effect_row;
    world_row.world_ports = 1;
    world_row.fingerprint = world_row.computeFingerprint();
    const world_normal_form = Elaboration.NormalForm.init("world-elaboration-normal-form", .strict_closed, closure_certificate_ref, world_row.evidenceRef(), 0);
    const world_certificate = Elaboration.Certificate.init(.{
        .elaborated_program_label = "strict-elaboration",
        .source_program_ref = source_ref,
        .residual_program_ref = residual_ref,
        .closure_certificate_ref = closure_certificate_ref,
        .closure_graph_ref = closure_graph_ref,
        .closure_report_ref = closure_report_ref,
        .source_map_ref = source_map.evidenceRef(),
        .effect_row_ref = world_row.evidenceRef(),
        .trace_map_ref = trace_map.evidenceRef(),
        .normal_form_ref = world_normal_form.evidenceRef(),
        .policy = policy,
        .normal_form = .strict_closed,
        .dependencies = dependencies[0..],
    });
    try std.testing.expectEqual(
        error.BoundaryElaborationCertificateMismatch,
        world_certificate.check(policy, closure_graph_ref, closure_report_ref, closure_certificate_ref, source_map, world_row, trace_map, world_normal_form, &.{}, &.{}),
    );

    const residual_world_port_ref = Evidence.refFor(Evidence.domains.boundary_world_port, 0xE1A806, .{ .label = "residual-world" });
    var residual_world_row = effect_row;
    residual_world_row.residual_world_ports = 1;
    residual_world_row.fingerprint = residual_world_row.computeFingerprint();
    const residual_world_normal_form = Elaboration.NormalForm.init("residual-world-elaboration-normal-form", .strict_closed, closure_certificate_ref, residual_world_row.evidenceRef(), 0);
    const residual_world_certificate = Elaboration.Certificate.init(.{
        .elaborated_program_label = "strict-elaboration",
        .source_program_ref = source_ref,
        .residual_program_ref = residual_ref,
        .closure_certificate_ref = closure_certificate_ref,
        .closure_graph_ref = closure_graph_ref,
        .closure_report_ref = closure_report_ref,
        .source_map_ref = source_map.evidenceRef(),
        .effect_row_ref = residual_world_row.evidenceRef(),
        .trace_map_ref = trace_map.evidenceRef(),
        .normal_form_ref = residual_world_normal_form.evidenceRef(),
        .policy = policy,
        .normal_form = .strict_closed,
        .residual_world_port_refs = &.{residual_world_port_ref},
        .dependencies = dependencies[0..],
    });
    try std.testing.expectEqual(
        error.BoundaryElaborationCertificateMismatch,
        residual_world_certificate.check(policy, closure_graph_ref, closure_report_ref, closure_certificate_ref, source_map, residual_world_row, trace_map, residual_world_normal_form, &.{}, &.{}),
    );

    var blocker_policy = Elaboration.Policy.auditOnly();
    blocker_policy.require_program_backed_providers_for_internal_routes = false;
    blocker_policy.max_blockers = 1;
    const blocked_shape = Closure.EffectShape.init(.{
        .program_label = "blocked-root",
        .kind = .operation,
        .site_index = 1,
        .protocol_label = "blocked-root",
    });
    const blocked_shape_ref = blocked_shape.evidenceRef();
    const first_plan_blocker = Evidence.BoundaryClosureBlocker{
        .tag = .unsupported_shape_planning,
        .subject = blocked_shape_ref,
        .summary = "first blocker",
    };
    const second_plan_blocker = Evidence.BoundaryClosureBlocker{
        .tag = .unsupported_shape_planning,
        .subject = blocked_shape_ref,
        .primary = closure_certificate_ref,
        .summary = "second blocker",
    };
    const first_blocker_ref = Evidence.refForBoundaryClosureBlocker(first_plan_blocker.toEvidenceBlocker());
    const second_blocker_ref = Evidence.refForBoundaryClosureBlocker(second_plan_blocker.toEvidenceBlocker());
    const blocked_static_plan = Closure.StaticTreatyPlan.init(.{
        .label = "blocked-root.plan",
        .source_shape = blocked_shape,
        .selected_semantic_body = .unknown,
        .blockers = &.{ first_plan_blocker, second_plan_blocker },
    });
    const blocked_static_plan_ref = blocked_static_plan.evidenceRef();
    const partial_static_plans = [_]Closure.StaticTreatyPlan{ static_plan, blocked_static_plan };
    const partial_static_plan_refs = [_]Evidence.Ref{ static_plan_ref, blocked_static_plan_ref };
    const partial_source_map_entries = [_]Elaboration.SourceMap.Entry{
        source_map_entries[0],
        .{
            .source_ref = blocked_shape_ref,
            .residual_ref = residual_ref,
            .source_site_index = 1,
            .static_treaty_plan_ref = blocked_static_plan_ref,
            .disposition = .blocked,
            .label = "blocked-root",
        },
    };
    const partial_source_map = Elaboration.SourceMap.init("partial-elaboration-map", partial_source_map_entries[0..], &.{});
    const partial_trace_entries = [_]Elaboration.TraceMap.Entry{
        trace_entries[0],
        .{ .source_ref = blocked_shape_ref, .residual_ref = residual_ref, .trace_label = "blocked-root" },
    };
    const partial_trace_map = Elaboration.TraceMap.init("partial-elaboration-trace", partial_trace_entries[0..]);
    const blocker_row = Elaboration.EffectRow.init(.{
        .label = "blocked-elaboration-row",
        .source_program_ref = source_ref,
        .residual_program_ref = residual_ref,
        .normal_form = .partial_with_blockers,
        .source_effect_shapes = 2,
        .closed_effect_shapes = 1,
        .blockers = 2,
        .unsupported_shapes = 1,
    });
    const blocker_normal_form = Elaboration.NormalForm.init("blocked-elaboration-normal-form", .partial_with_blockers, closure_certificate_ref, blocker_row.evidenceRef(), 2);
    const blocker_certificate = Elaboration.Certificate.init(.{
        .elaborated_program_label = "blocked-elaboration",
        .source_program_ref = source_ref,
        .residual_program_ref = residual_ref,
        .closure_certificate_ref = closure_certificate_ref,
        .closure_graph_ref = closure_graph_ref,
        .closure_report_ref = closure_report_ref,
        .source_map_ref = partial_source_map.evidenceRef(),
        .effect_row_ref = blocker_row.evidenceRef(),
        .trace_map_ref = partial_trace_map.evidenceRef(),
        .normal_form_ref = blocker_normal_form.evidenceRef(),
        .policy = blocker_policy,
        .normal_form = .partial_with_blockers,
        .selected_static_treaty_plan_refs = partial_static_plan_refs[0..],
        .blocker_refs = &.{ first_blocker_ref, second_blocker_ref },
        .summary_counts = .{
            .root_effect_shapes = 2,
            .internal_routes_elaborated = 1,
            .blockers = 2,
        },
        .dependencies = dependencies[0..],
    });
    try std.testing.expectEqual(
        error.BoundaryElaborationBlocked,
        blocker_certificate.check(blocker_policy, closure_graph_ref, closure_report_ref, closure_certificate_ref, partial_source_map, blocker_row, partial_trace_map, blocker_normal_form, partial_static_plans[0..], &.{}),
    );
    var unbounded_blocker_policy = blocker_policy;
    unbounded_blocker_policy.max_blockers = 2;
    const valid_blocker_refs = Elaboration.Certificate.init(.{
        .elaborated_program_label = "blocked-elaboration",
        .source_program_ref = source_ref,
        .residual_program_ref = residual_ref,
        .closure_certificate_ref = closure_certificate_ref,
        .closure_graph_ref = closure_graph_ref,
        .closure_report_ref = closure_report_ref,
        .source_map_ref = partial_source_map.evidenceRef(),
        .effect_row_ref = blocker_row.evidenceRef(),
        .trace_map_ref = partial_trace_map.evidenceRef(),
        .normal_form_ref = blocker_normal_form.evidenceRef(),
        .policy = unbounded_blocker_policy,
        .normal_form = .partial_with_blockers,
        .selected_static_treaty_plan_refs = partial_static_plan_refs[0..],
        .blocker_refs = &.{ first_blocker_ref, second_blocker_ref },
        .summary_counts = .{
            .root_effect_shapes = 2,
            .internal_routes_elaborated = 1,
            .blockers = 2,
        },
        .dependencies = dependencies[0..],
    });
    try valid_blocker_refs.check(unbounded_blocker_policy, closure_graph_ref, closure_report_ref, closure_certificate_ref, partial_source_map, blocker_row, partial_trace_map, blocker_normal_form, partial_static_plans[0..], &.{});
    const empty_blocker_source_map = Elaboration.SourceMap.init("partial-elaboration-empty-blocker-map", &.{}, &.{});
    const empty_blocker_trace_map = Elaboration.TraceMap.init("partial-elaboration-empty-blocker-trace", &.{});
    const unanchored_blocker_row = Elaboration.EffectRow.init(.{
        .label = "partial-elaboration-unanchored-blocker-row",
        .source_program_ref = source_ref,
        .residual_program_ref = residual_ref,
        .normal_form = .partial_with_blockers,
        .blockers = 1,
    });
    const unanchored_blocker_normal_form = Elaboration.NormalForm.init("partial-elaboration-unanchored-blocker-normal-form", .partial_with_blockers, closure_certificate_ref, unanchored_blocker_row.evidenceRef(), 1);
    const unanchored_blocker_certificate = Elaboration.Certificate.init(.{
        .elaborated_program_label = "partial-elaboration-unanchored-blocker",
        .source_program_ref = source_ref,
        .residual_program_ref = residual_ref,
        .closure_certificate_ref = closure_certificate_ref,
        .closure_graph_ref = closure_graph_ref,
        .closure_report_ref = closure_report_ref,
        .source_map_ref = empty_blocker_source_map.evidenceRef(),
        .effect_row_ref = unanchored_blocker_row.evidenceRef(),
        .trace_map_ref = empty_blocker_trace_map.evidenceRef(),
        .normal_form_ref = unanchored_blocker_normal_form.evidenceRef(),
        .policy = unbounded_blocker_policy,
        .normal_form = .partial_with_blockers,
        .blocker_refs = &.{first_blocker_ref},
        .summary_counts = .{ .blockers = 1 },
        .dependencies = dependencies[0..],
    });
    try std.testing.expectEqual(
        error.BoundaryElaborationCertificateMismatch,
        unanchored_blocker_certificate.check(unbounded_blocker_policy, closure_graph_ref, closure_report_ref, closure_certificate_ref, empty_blocker_source_map, unanchored_blocker_row, empty_blocker_trace_map, unanchored_blocker_normal_form, &.{}, &.{}),
    );
    const direct_shape_blocker = Evidence.BoundaryClosureBlocker{
        .tag = .duplicate_effect_shape,
        .subject = blocked_shape_ref,
        .summary = "direct shape blocker",
    };
    const direct_shape_blocker_ref = Evidence.refForBoundaryClosureBlocker(direct_shape_blocker.toEvidenceBlocker());
    const mixed_direct_entries = [_]Elaboration.SourceMap.Entry{
        partial_source_map_entries[0],
        partial_source_map_entries[1],
        .{
            .source_ref = blocked_shape_ref,
            .residual_ref = residual_ref,
            .source_site_index = 1,
            .blocker_ref = direct_shape_blocker_ref,
            .disposition = .blocked,
            .label = "direct-shape-blocker",
        },
    };
    const mixed_direct_map = Elaboration.SourceMap.init("partial-elaboration-direct-shape-blocker-map", mixed_direct_entries[0..], &.{});
    const mixed_direct_trace_entries = [_]Elaboration.TraceMap.Entry{
        partial_trace_entries[0],
        partial_trace_entries[1],
        .{ .source_ref = blocked_shape_ref, .residual_ref = residual_ref, .trace_label = "direct-shape-blocker" },
    };
    const mixed_direct_trace_map = Elaboration.TraceMap.init("partial-elaboration-direct-shape-blocker-trace", mixed_direct_trace_entries[0..]);
    const mixed_direct_row = Elaboration.EffectRow.init(.{
        .label = "blocked-elaboration-direct-shape-row",
        .source_program_ref = source_ref,
        .residual_program_ref = residual_ref,
        .normal_form = .partial_with_blockers,
        .source_effect_shapes = 2,
        .closed_effect_shapes = 1,
        .blockers = 3,
        .unsupported_shapes = 1,
    });
    var direct_blocker_policy = unbounded_blocker_policy;
    direct_blocker_policy.max_blockers = 3;
    const mixed_direct_normal_form = Elaboration.NormalForm.init("blocked-elaboration-direct-shape-normal-form", .partial_with_blockers, closure_certificate_ref, mixed_direct_row.evidenceRef(), 3);
    const mixed_direct_certificate = Elaboration.Certificate.init(.{
        .elaborated_program_label = "blocked-elaboration",
        .source_program_ref = source_ref,
        .residual_program_ref = residual_ref,
        .closure_certificate_ref = closure_certificate_ref,
        .closure_graph_ref = closure_graph_ref,
        .closure_report_ref = closure_report_ref,
        .source_map_ref = mixed_direct_map.evidenceRef(),
        .effect_row_ref = mixed_direct_row.evidenceRef(),
        .trace_map_ref = mixed_direct_trace_map.evidenceRef(),
        .normal_form_ref = mixed_direct_normal_form.evidenceRef(),
        .policy = direct_blocker_policy,
        .normal_form = .partial_with_blockers,
        .selected_static_treaty_plan_refs = partial_static_plan_refs[0..],
        .blocker_refs = &.{ first_blocker_ref, second_blocker_ref, direct_shape_blocker_ref },
        .summary_counts = .{
            .root_effect_shapes = 2,
            .internal_routes_elaborated = 1,
            .blockers = 3,
        },
        .dependencies = dependencies[0..],
    });
    try mixed_direct_certificate.check(direct_blocker_policy, closure_graph_ref, closure_report_ref, closure_certificate_ref, mixed_direct_map, mixed_direct_row, mixed_direct_trace_map, mixed_direct_normal_form, partial_static_plans[0..], &.{});
    const static_entry_forged_blocker = Evidence.refFor(Evidence.domains.boundary_closure_report, 0xE1A819, .{ .kind_tag = "static_entry_forged_blocker" });
    const forged_static_blocker_entries = [_]Elaboration.SourceMap.Entry{
        source_map_entries[0],
        .{
            .source_ref = blocked_shape_ref,
            .residual_ref = residual_ref,
            .source_site_index = 1,
            .static_treaty_plan_ref = blocked_static_plan_ref,
            .blocker_ref = static_entry_forged_blocker,
            .disposition = .blocked,
            .label = "blocked-root",
        },
    };
    const forged_static_blocker_map = Elaboration.SourceMap.init("partial-elaboration-forged-static-blocker-map", forged_static_blocker_entries[0..], &.{});
    const forged_static_blocker_cert = Elaboration.Certificate.init(.{
        .elaborated_program_label = "blocked-elaboration",
        .source_program_ref = source_ref,
        .residual_program_ref = residual_ref,
        .closure_certificate_ref = closure_certificate_ref,
        .closure_graph_ref = closure_graph_ref,
        .closure_report_ref = closure_report_ref,
        .source_map_ref = forged_static_blocker_map.evidenceRef(),
        .effect_row_ref = blocker_row.evidenceRef(),
        .trace_map_ref = partial_trace_map.evidenceRef(),
        .normal_form_ref = blocker_normal_form.evidenceRef(),
        .policy = unbounded_blocker_policy,
        .normal_form = .partial_with_blockers,
        .selected_static_treaty_plan_refs = partial_static_plan_refs[0..],
        .blocker_refs = &.{ first_blocker_ref, second_blocker_ref },
        .summary_counts = .{
            .root_effect_shapes = 2,
            .internal_routes_elaborated = 1,
            .blockers = 2,
        },
        .dependencies = dependencies[0..],
    });
    try std.testing.expectEqual(
        error.BoundaryElaborationCertificateMismatch,
        forged_static_blocker_cert.check(unbounded_blocker_policy, closure_graph_ref, closure_report_ref, closure_certificate_ref, forged_static_blocker_map, blocker_row, partial_trace_map, blocker_normal_form, partial_static_plans[0..], &.{}),
    );
    const forged_blocker_refs = [_]Evidence.Ref{
        Evidence.refFor(Evidence.domains.boundary_closure_report, 0xE1A807, .{ .kind_tag = "first_blocker" }),
        Evidence.refFor(Evidence.domains.boundary_closure_report, 0xE1A808, .{ .kind_tag = "second_blocker" }),
    };
    const forged_blocker_identity = Elaboration.Certificate.init(.{
        .elaborated_program_label = "blocked-elaboration",
        .source_program_ref = source_ref,
        .residual_program_ref = residual_ref,
        .closure_certificate_ref = closure_certificate_ref,
        .closure_graph_ref = closure_graph_ref,
        .closure_report_ref = closure_report_ref,
        .source_map_ref = partial_source_map.evidenceRef(),
        .effect_row_ref = blocker_row.evidenceRef(),
        .trace_map_ref = partial_trace_map.evidenceRef(),
        .normal_form_ref = blocker_normal_form.evidenceRef(),
        .policy = unbounded_blocker_policy,
        .normal_form = .partial_with_blockers,
        .selected_static_treaty_plan_refs = partial_static_plan_refs[0..],
        .blocker_refs = forged_blocker_refs[0..],
        .summary_counts = .{
            .root_effect_shapes = 2,
            .internal_routes_elaborated = 1,
            .blockers = 2,
        },
        .dependencies = dependencies[0..],
    });
    try std.testing.expectEqual(
        error.BoundaryElaborationCertificateMismatch,
        forged_blocker_identity.check(unbounded_blocker_policy, closure_graph_ref, closure_report_ref, closure_certificate_ref, partial_source_map, blocker_row, partial_trace_map, blocker_normal_form, partial_static_plans[0..], &.{}),
    );
    const omitted_blocker_refs = Elaboration.Certificate.init(.{
        .elaborated_program_label = "blocked-elaboration",
        .source_program_ref = source_ref,
        .residual_program_ref = residual_ref,
        .closure_certificate_ref = closure_certificate_ref,
        .closure_graph_ref = closure_graph_ref,
        .closure_report_ref = closure_report_ref,
        .source_map_ref = partial_source_map.evidenceRef(),
        .effect_row_ref = blocker_row.evidenceRef(),
        .trace_map_ref = partial_trace_map.evidenceRef(),
        .normal_form_ref = blocker_normal_form.evidenceRef(),
        .policy = unbounded_blocker_policy,
        .normal_form = .partial_with_blockers,
        .selected_static_treaty_plan_refs = partial_static_plan_refs[0..],
        .summary_counts = .{
            .root_effect_shapes = 2,
            .internal_routes_elaborated = 1,
            .blockers = 2,
        },
        .dependencies = dependencies[0..],
    });
    try std.testing.expectEqual(
        error.BoundaryElaborationCertificateMismatch,
        omitted_blocker_refs.check(unbounded_blocker_policy, closure_graph_ref, closure_report_ref, closure_certificate_ref, partial_source_map, blocker_row, partial_trace_map, blocker_normal_form, partial_static_plans[0..], &.{}),
    );
    const blockerless_partial_row = Elaboration.EffectRow.init(.{
        .label = "blockerless-partial-elaboration-row",
        .source_program_ref = source_ref,
        .residual_program_ref = residual_ref,
        .normal_form = .partial_with_blockers,
        .source_effect_shapes = 2,
        .closed_effect_shapes = 1,
        .unsupported_shapes = 1,
    });
    const blockerless_partial_normal = Elaboration.NormalForm.init("blockerless-partial-normal-form", .partial_with_blockers, closure_certificate_ref, blockerless_partial_row.evidenceRef(), 0);
    const blockerless_partial_certificate = Elaboration.Certificate.init(.{
        .elaborated_program_label = "blockerless-partial-elaboration",
        .source_program_ref = source_ref,
        .residual_program_ref = residual_ref,
        .closure_certificate_ref = closure_certificate_ref,
        .closure_graph_ref = closure_graph_ref,
        .closure_report_ref = closure_report_ref,
        .source_map_ref = partial_source_map.evidenceRef(),
        .effect_row_ref = blockerless_partial_row.evidenceRef(),
        .trace_map_ref = partial_trace_map.evidenceRef(),
        .normal_form_ref = blockerless_partial_normal.evidenceRef(),
        .policy = unbounded_blocker_policy,
        .normal_form = .partial_with_blockers,
        .selected_static_treaty_plan_refs = partial_static_plan_refs[0..],
        .summary_counts = .{
            .root_effect_shapes = 2,
            .internal_routes_elaborated = 1,
        },
        .dependencies = dependencies[0..],
    });
    try std.testing.expectEqual(
        error.BoundaryElaborationCertificateMismatch,
        blockerless_partial_certificate.check(unbounded_blocker_policy, closure_graph_ref, closure_report_ref, closure_certificate_ref, partial_source_map, blockerless_partial_row, partial_trace_map, blockerless_partial_normal, partial_static_plans[0..], &.{}),
    );
}

test "certified boundary target world surface tables and certificate are deterministic" {
    const Elaboration = Program.BoundaryClosure.Elaboration;
    const value_ref = Evidence.BoundaryValueRef.init("i32", null);
    const source_shape = Evidence.BoundaryEffectShape.init(.{
        .program_label = "residual",
        .kind = .operation,
        .site_index = 0,
        .site_fingerprint = 0xC781_0005,
        .semantic_label = "approval.request",
        .name = "request",
        .mode = "transform",
        .value_ref = value_ref,
        .expected_resume_ref = value_ref,
        .result_ref = value_ref,
        .protocol_label = "approval",
        .protocol_op_fingerprint = 0xC781_0005,
    });
    const source_ref = source_shape.evidenceRef();
    const static_plan = Evidence.BoundaryStaticTreatyPlan.init(.{
        .label = "target.static-plan",
        .source_shape = source_shape,
        .selected_semantic_body = .declarative,
    });
    const static_plans = [_]Evidence.BoundaryStaticTreatyPlan{static_plan};
    const world_port = Evidence.BoundaryWorldPort.init(.{
        .label = "world-port",
        .kind = .host_human,
        .effect_shape_ref = source_ref,
        .supported_site_indexes = &.{ 0, 5 },
        .contract_summary = "approval request boundary",
    });
    const world_ports = [_]Evidence.BoundaryWorldPort{world_port};
    const world_port_ref = world_port.evidenceRef();
    const residual_program_ref = Evidence.refFor(Evidence.domains.program_plan, 0xC781_0003, .{ .label = "residual" });
    const closure_graph_ref = Evidence.refFor(Evidence.domains.boundary_closure_graph, 0xC781_0004, .{ .label = "target.closure-graph" });
    const closure_report_ref = Evidence.refFor(Evidence.domains.boundary_closure_report, 0xC781_0006, .{ .label = "target.closure-report" });
    const closure_certificate_ref = Evidence.refFor(Evidence.domains.boundary_closure_certificate, 0xC781_0007, .{ .label = "target.closure-certificate" });
    const entries = [_]Elaboration.WorldPortTable.Entry{.{
        .world_port_id = 0,
        .residual_site_index = 0,
        .residual_site_fingerprint = 0xC781_0005,
        .world_port_ref = world_port_ref,
        .source_ref = source_ref,
        .payload_ref = value_ref,
        .resume_ref = value_ref,
        .result_ref = value_ref,
        .protocol_label = "approval",
        .op_name = "request",
        .mode = "transform",
        .semantic_label = "approval.request",
    }};
    const port_table = Elaboration.WorldPortTable.init("target.ports", entries[0..]);
    const value_entries = [_]Elaboration.WorldValueTable.Entry{
        .{ .value_id = 0, .world_port_id = 0, .kind = .payload, .ref = value_ref },
        .{ .value_id = 1, .world_port_id = 0, .kind = .@"resume", .ref = value_ref },
        .{ .value_id = 2, .world_port_id = 0, .kind = .result, .ref = value_ref },
    };
    const value_table = Elaboration.WorldValueTable.init("target.values", value_entries[0..]);
    const dispatch_entries = [_]Elaboration.WorldDispatchTable.Entry{.{
        .residual_site_index = 0,
        .residual_site_fingerprint = 0xC781_0005,
        .world_port_id = 0,
    }};
    const dispatch_table = Elaboration.WorldDispatchTable.init("target.dispatch", dispatch_entries[0..]);
    const profile = Elaboration.SurfaceProfile.init(.{
        .label = "target.profile",
        .world_port_count = port_table.entries.len,
        .value_descriptor_count = value_table.entries.len,
        .dispatch_entry_count = dispatch_table.entries.len,
        .no_search_hot_path = true,
        .bounded = true,
    });
    const source_entries = [_]Elaboration.SourceMap.Entry{.{
        .source_ref = source_ref,
        .residual_ref = residual_program_ref,
        .source_site_index = 0,
        .residual_site_index = 0,
        .static_treaty_plan_ref = static_plan.evidenceRef(),
        .world_port_ref = world_port_ref,
        .disposition = .world_port_lowered,
        .label = "target.source-entry",
    }};
    const source_map = Elaboration.SourceMap.init("target.source-map", source_entries[0..], &.{});
    const trace_entries = [_]Elaboration.TraceMap.Entry{.{
        .source_ref = source_ref,
        .residual_ref = world_port_ref,
        .trace_label = "target.source-entry",
    }};
    const trace_map = Elaboration.TraceMap.init("target.trace-map", trace_entries[0..]);
    const trace_map_ref = trace_map.evidenceRef();
    const effect_row = Elaboration.EffectRow.init(.{
        .label = "target.effect-row",
        .source_program_ref = residual_program_ref,
        .residual_program_ref = residual_program_ref,
        .normal_form = .world_ports_only,
        .source_effect_shapes = 1,
        .world_ports = 1,
    });
    const normal_form = Elaboration.NormalForm.init("target.normal-form", .world_ports_only, closure_certificate_ref, effect_row.evidenceRef(), 0);
    const policy = Elaboration.Target.Policy.worldBoundary();
    const target_elaboration_policy = policy.toElaborationPolicy();
    try std.testing.expect(target_elaboration_policy.closure_policy.allow_world_ports);
    try std.testing.expect(!target_elaboration_policy.closure_policy.require_all_effect_shapes_closed);
    try std.testing.expect(target_elaboration_policy.closure_policy.allowsWorldPortRef(world_port_ref));
    const elaboration_certificate = Elaboration.Certificate.init(.{
        .elaborated_program_label = "target.elaboration",
        .source_program_ref = residual_program_ref,
        .residual_program_ref = residual_program_ref,
        .closure_certificate_ref = closure_certificate_ref,
        .closure_graph_ref = closure_graph_ref,
        .closure_report_ref = closure_report_ref,
        .source_map_ref = source_map.evidenceRef(),
        .effect_row_ref = effect_row.evidenceRef(),
        .trace_map_ref = trace_map_ref,
        .normal_form_ref = normal_form.evidenceRef(),
        .policy = target_elaboration_policy,
        .normal_form = .world_ports_only,
        .selected_static_treaty_plan_refs = &.{static_plan.evidenceRef()},
        .world_port_refs = &.{world_port_ref},
        .residual_world_port_refs = &.{world_port_ref},
        .summary_counts = .{
            .root_effect_shapes = 1,
            .world_ports_emitted = 1,
        },
    });
    const elaboration_certificate_ref = elaboration_certificate.evidenceRef();
    const surface_scope = Elaboration.WorldSurface.init(.{
        .label = "target.surface",
        .residual_program_label = "residual",
        .residual_program_ref = residual_program_ref,
        .elaboration_certificate_ref = elaboration_certificate_ref,
        .source_map_ref = source_map.evidenceRef(),
        .effect_row_ref = effect_row.evidenceRef(),
        .port_table_ref = port_table.evidenceRef(),
        .value_table_ref = value_table.evidenceRef(),
        .dispatch_table_ref = dispatch_table.evidenceRef(),
        .profile_ref = profile.evidenceRef(),
        .replay_key_recipe_ref = elaboration_certificate_ref,
        .normal_form = .world_ports_only,
        .world_port_count = 1,
    });
    const replay = Elaboration.ReplayKeyRecipe.init("target.replay", surface_scope.replayScopeRef(), &.{ "world_surface_scope_fingerprint", "world_port_id", "request_fingerprint", "response_fingerprint" });
    const surface = Elaboration.WorldSurface.init(.{
        .label = surface_scope.label,
        .residual_program_label = surface_scope.residual_program_label,
        .residual_program_ref = surface_scope.residual_program_ref,
        .elaboration_certificate_ref = surface_scope.elaboration_certificate_ref,
        .source_map_ref = surface_scope.source_map_ref,
        .effect_row_ref = surface_scope.effect_row_ref,
        .port_table_ref = surface_scope.port_table_ref,
        .value_table_ref = surface_scope.value_table_ref,
        .dispatch_table_ref = surface_scope.dispatch_table_ref,
        .profile_ref = surface_scope.profile_ref,
        .replay_key_recipe_ref = replay.evidenceRef(),
        .normal_form = surface_scope.normal_form,
        .world_port_count = surface_scope.world_port_count,
    });
    const dependencies = [_]Evidence.Dependency{
        .{ .role = .elaboration_certificate, .ref = elaboration_certificate_ref },
        .{ .role = .elaboration_source_map, .ref = surface.source_map_ref },
        .{ .role = .elaboration_effect_row, .ref = surface.effect_row_ref },
        .{ .role = .elaboration_trace_map, .ref = trace_map_ref },
        .{ .role = .world_surface, .ref = surface.evidenceRef() },
        .{ .role = .world_port_table, .ref = port_table.evidenceRef() },
        .{ .role = .world_value_table, .ref = value_table.evidenceRef() },
        .{ .role = .world_dispatch_table, .ref = dispatch_table.evidenceRef() },
        .{ .role = .surface_profile, .ref = profile.evidenceRef() },
        .{ .role = .replay_key_recipe, .ref = replay.evidenceRef() },
        .{ .role = .residual_program, .ref = residual_program_ref },
    };
    const evidence_map = Elaboration.TargetEvidenceMap.init("target.evidence", dependencies[0..]);
    const normalization_redex_dependencies = [_]Evidence.Dependency{
        .{ .role = .source, .ref = source_ref },
        .{ .role = .residual_program, .ref = residual_program_ref },
    };
    const normalization_redex = Elaboration.Target.Normalization.Redex.init(.{
        .label = "target.source-entry",
        .source_effect_shape_ref = source_ref,
        .coordinates = .{ .function_index = 0, .block_index = 0, .instruction_index = 0, .site_index = 0 },
        .kind = .world_port_site,
        .selected_static_treaty_plan_ref = static_plan.evidenceRef(),
        .current_program_plan_ref = residual_program_ref,
        .semantic_body = .declarative,
        .expected_lowering_kind = .residual_world_port,
        .evidence_dependencies = normalization_redex_dependencies[0..],
    });
    const normalization_rule_dependencies = [_]Evidence.Dependency{.{ .role = .source, .ref = source_ref }};
    const normalization_rule = Elaboration.Target.Normalization.RewriteRule.init(.{
        .label = "target.source-entry",
        .kind = .residual_world_port,
        .evidence_dependencies = normalization_rule_dependencies[0..],
        .produced_source_map_entries = 1,
        .produced_trace_map_entries = 1,
        .produced_effect_row_entries = 1,
    });
    const normalization_route_lowering_fingerprint = Evidence.boundaryNormalizationRouteLoweringFingerprint(source_entries[0], residual_program_ref.fingerprint);
    const normalization_step = Elaboration.Target.Normalization.RewriteStep.init(.{
        .step_index = 0,
        .redex_ref = normalization_redex.evidenceRef(),
        .rewrite_rule_ref = normalization_rule.evidenceRef(),
        .selected_static_treaty_plan_ref = static_plan.evidenceRef(),
        .source_effect_shape_ref = source_ref,
        .input_program_plan_hash = residual_program_ref.fingerprint,
        .output_program_plan_hash = residual_program_ref.fingerprint,
        .builder_state_fingerprint = normalization_route_lowering_fingerprint,
        .world_port_ref = world_port_ref,
        .summary = "residual_world_port",
    });
    const normalization_redexes = [_]Elaboration.Target.Normalization.Redex{normalization_redex};
    const normalization_rules = [_]Elaboration.Target.Normalization.RewriteRule{normalization_rule};
    const normalization_steps = [_]Elaboration.Target.Normalization.RewriteStep{normalization_step};
    const normalization_world_ports = [_]Evidence.Ref{world_port_ref};
    const normalization_trace_dependencies = [_]Evidence.Dependency{
        .{ .role = .closure_certificate, .ref = closure_certificate_ref },
        .{ .role = .residual_program, .ref = residual_program_ref },
        .{ .role = .elaboration_source_map, .ref = source_map.evidenceRef() },
        .{ .role = .elaboration_effect_row, .ref = effect_row.evidenceRef() },
        .{ .role = .normal_form, .ref = normal_form.evidenceRef() },
    };
    const normalization_trace = Elaboration.Target.Normalization.Trace.init(.{
        .label = "target.normalization.trace",
        .root_program_ref = residual_program_ref,
        .closure_certificate_ref = closure_certificate_ref,
        .rewrite_steps = normalization_steps[0..],
        .residual_world_port_refs = normalization_world_ports[0..],
        .final_program_plan_hash = residual_program_ref.fingerprint,
        .final_normal_form = .world_ports_only,
        .evidence_dependencies = normalization_trace_dependencies[0..],
    });
    const normalization_certificate_dependencies = [_]Evidence.Dependency{
        .{ .role = .normalization_trace, .ref = normalization_trace.evidenceRef() },
        .{ .role = .elaboration_source_map, .ref = source_map.evidenceRef() },
        .{ .role = .elaboration_trace_map, .ref = trace_map.evidenceRef() },
        .{ .role = .target_evidence_map, .ref = evidence_map.evidenceRef() },
        .{ .role = .elaboration_effect_row, .ref = effect_row.evidenceRef() },
        .{ .role = .normal_form, .ref = normal_form.evidenceRef() },
        .{ .role = .world_surface, .ref = surface.evidenceRef() },
    };
    const normalization_certificate = Elaboration.Target.Normalization.Certificate.init(.{
        .label = "target.normalization.certificate",
        .closure_certificate_ref = closure_certificate_ref,
        .target_policy_fingerprint = policy.fingerprint(),
        .normalization_trace_ref = normalization_trace.evidenceRef(),
        .final_program_plan_hash = residual_program_ref.fingerprint,
        .source_map_ref = source_map.evidenceRef(),
        .trace_map_ref = trace_map.evidenceRef(),
        .evidence_map_ref = evidence_map.evidenceRef(),
        .effect_row_ref = effect_row.evidenceRef(),
        .normal_form_ref = normal_form.evidenceRef(),
        .world_surface_ref = surface.evidenceRef(),
        .dependencies = normalization_certificate_dependencies[0..],
    });
    const certificate_dependencies = dependencies ++ [_]Evidence.Dependency{
        .{ .role = .normalization_certificate, .ref = normalization_certificate.evidenceRef() },
    };
    const certificate = Elaboration.Target.Certificate.init(.{
        .target_label = "target",
        .policy = policy,
        .elaboration_certificate_ref = elaboration_certificate_ref,
        .residual_program_ref = residual_program_ref,
        .world_surface_ref = surface.evidenceRef(),
        .port_table_ref = port_table.evidenceRef(),
        .value_table_ref = value_table.evidenceRef(),
        .dispatch_table_ref = dispatch_table.evidenceRef(),
        .profile_ref = profile.evidenceRef(),
        .replay_key_recipe_ref = replay.evidenceRef(),
        .evidence_map_ref = evidence_map.evidenceRef(),
        .trace_map_ref = trace_map_ref,
        .normalization_certificate_ref = normalization_certificate.evidenceRef(),
        .dependencies = certificate_dependencies[0..],
    });
    try certificate.check(policy, elaboration_certificate, surface, source_map, effect_row, trace_map, normal_form, world_ports[0..], port_table, value_table, dispatch_table, profile, replay, evidence_map, normalization_certificate, normalization_trace, normalization_redexes[0..], normalization_rules[0..], static_plans[0..]);

    const missing_normalization_dependency = Elaboration.Target.Certificate.init(.{
        .target_label = "target.missing-normalization-dependency",
        .policy = policy,
        .elaboration_certificate_ref = elaboration_certificate_ref,
        .residual_program_ref = residual_program_ref,
        .world_surface_ref = surface.evidenceRef(),
        .port_table_ref = port_table.evidenceRef(),
        .value_table_ref = value_table.evidenceRef(),
        .dispatch_table_ref = dispatch_table.evidenceRef(),
        .profile_ref = profile.evidenceRef(),
        .replay_key_recipe_ref = replay.evidenceRef(),
        .evidence_map_ref = evidence_map.evidenceRef(),
        .trace_map_ref = trace_map_ref,
        .normalization_certificate_ref = normalization_certificate.evidenceRef(),
        .dependencies = dependencies[0..],
    });
    try std.testing.expectEqual(
        error.BoundaryTargetCertificateMismatch,
        missing_normalization_dependency.check(policy, elaboration_certificate, surface, source_map, effect_row, trace_map, normal_form, world_ports[0..], port_table, value_table, dispatch_table, profile, replay, evidence_map, normalization_certificate, normalization_trace, normalization_redexes[0..], normalization_rules[0..], static_plans[0..]),
    );

    const missing_normalization_certificate = Elaboration.Target.Certificate.init(.{
        .target_label = "target.missing-normalization",
        .policy = policy,
        .elaboration_certificate_ref = elaboration_certificate_ref,
        .residual_program_ref = residual_program_ref,
        .world_surface_ref = surface.evidenceRef(),
        .port_table_ref = port_table.evidenceRef(),
        .value_table_ref = value_table.evidenceRef(),
        .dispatch_table_ref = dispatch_table.evidenceRef(),
        .profile_ref = profile.evidenceRef(),
        .replay_key_recipe_ref = replay.evidenceRef(),
        .evidence_map_ref = evidence_map.evidenceRef(),
        .trace_map_ref = trace_map_ref,
        .dependencies = certificate_dependencies[0..],
    });
    try std.testing.expectEqual(
        error.BoundaryTargetCertificateMismatch,
        missing_normalization_certificate.check(policy, elaboration_certificate, surface, source_map, effect_row, trace_map, normal_form, world_ports[0..], port_table, value_table, dispatch_table, profile, replay, evidence_map, normalization_certificate, normalization_trace, normalization_redexes[0..], normalization_rules[0..], static_plans[0..]),
    );

    const forged_normalization_ref = Evidence.refFor(Evidence.domains.boundary_normalization_certificate, 0xF0A6_ED, .{ .label = "forged-normalization" });
    const forged_normalization_dependencies = dependencies ++ [_]Evidence.Dependency{
        .{ .role = .normalization_certificate, .ref = forged_normalization_ref },
    };
    const forged_normalization_certificate = Elaboration.Target.Certificate.init(.{
        .target_label = "target.forged-normalization",
        .policy = policy,
        .elaboration_certificate_ref = elaboration_certificate_ref,
        .residual_program_ref = residual_program_ref,
        .world_surface_ref = surface.evidenceRef(),
        .port_table_ref = port_table.evidenceRef(),
        .value_table_ref = value_table.evidenceRef(),
        .dispatch_table_ref = dispatch_table.evidenceRef(),
        .profile_ref = profile.evidenceRef(),
        .replay_key_recipe_ref = replay.evidenceRef(),
        .evidence_map_ref = evidence_map.evidenceRef(),
        .trace_map_ref = trace_map_ref,
        .normalization_certificate_ref = forged_normalization_ref,
        .dependencies = forged_normalization_dependencies[0..],
    });
    try std.testing.expectEqual(
        error.BoundaryTargetCertificateMismatch,
        forged_normalization_certificate.check(policy, elaboration_certificate, surface, source_map, effect_row, trace_map, normal_form, world_ports[0..], port_table, value_table, dispatch_table, profile, replay, evidence_map, normalization_certificate, normalization_trace, normalization_redexes[0..], normalization_rules[0..], static_plans[0..]),
    );

    try std.testing.expectEqual(@as(usize, 1), surface.world_port_count);
    try std.testing.expectEqual(@as(u32, 0), port_table.entries[0].world_port_id);
    try std.testing.expectEqual(@as(usize, 3), value_table.entries.len);
    try std.testing.expectEqual(@as(u32, 0), dispatch_table.entries[0].world_port_id);
    try std.testing.expect(profile.no_search_hot_path);
    try std.testing.expect(certificate.evidenceView().certificate_ref.eql(certificate.evidenceRef()));
    try std.testing.expectEqualStrings("target.surface", surface.evidenceRef().label.?);

    var stale_elaboration_certificate = elaboration_certificate;
    stale_elaboration_certificate.closure_certificate_ref = Evidence.refFor(Evidence.domains.boundary_closure_certificate, 0xC781_F0C1, .{ .label = "target.stale-closure-certificate" });
    try std.testing.expectEqual(
        error.BoundaryTargetCertificateMismatch,
        certificate.check(policy, stale_elaboration_certificate, surface, source_map, effect_row, trace_map, normal_form, world_ports[0..], port_table, value_table, dispatch_table, profile, replay, evidence_map, normalization_certificate, normalization_trace, normalization_redexes[0..], normalization_rules[0..], static_plans[0..]),
    );

    var forged_static_refs_elaboration_certificate = elaboration_certificate;
    forged_static_refs_elaboration_certificate.selected_static_treaty_plan_refs = &.{};
    forged_static_refs_elaboration_certificate.certificate_fingerprint = forged_static_refs_elaboration_certificate.computeFingerprint();
    const forged_static_refs_elaboration_certificate_ref = forged_static_refs_elaboration_certificate.evidenceRef();
    const forged_static_refs_surface_scope = Elaboration.WorldSurface.init(.{
        .label = "target.forged-static-refs-surface",
        .residual_program_label = "residual",
        .residual_program_ref = residual_program_ref,
        .elaboration_certificate_ref = forged_static_refs_elaboration_certificate_ref,
        .source_map_ref = source_map.evidenceRef(),
        .effect_row_ref = effect_row.evidenceRef(),
        .port_table_ref = port_table.evidenceRef(),
        .value_table_ref = value_table.evidenceRef(),
        .dispatch_table_ref = dispatch_table.evidenceRef(),
        .profile_ref = profile.evidenceRef(),
        .replay_key_recipe_ref = forged_static_refs_elaboration_certificate_ref,
        .normal_form = .world_ports_only,
        .world_port_count = 1,
    });
    const forged_static_refs_replay = Elaboration.ReplayKeyRecipe.init("target.forged-static-refs-replay", forged_static_refs_surface_scope.replayScopeRef(), replay.components);
    const forged_static_refs_surface = Elaboration.WorldSurface.init(.{
        .label = forged_static_refs_surface_scope.label,
        .residual_program_label = forged_static_refs_surface_scope.residual_program_label,
        .residual_program_ref = forged_static_refs_surface_scope.residual_program_ref,
        .elaboration_certificate_ref = forged_static_refs_surface_scope.elaboration_certificate_ref,
        .source_map_ref = forged_static_refs_surface_scope.source_map_ref,
        .effect_row_ref = forged_static_refs_surface_scope.effect_row_ref,
        .port_table_ref = forged_static_refs_surface_scope.port_table_ref,
        .value_table_ref = forged_static_refs_surface_scope.value_table_ref,
        .dispatch_table_ref = forged_static_refs_surface_scope.dispatch_table_ref,
        .profile_ref = forged_static_refs_surface_scope.profile_ref,
        .replay_key_recipe_ref = forged_static_refs_replay.evidenceRef(),
        .normal_form = forged_static_refs_surface_scope.normal_form,
        .world_port_count = forged_static_refs_surface_scope.world_port_count,
    });
    const forged_static_refs_dependencies = [_]Evidence.Dependency{
        .{ .role = .elaboration_certificate, .ref = forged_static_refs_elaboration_certificate_ref },
        .{ .role = .elaboration_source_map, .ref = forged_static_refs_surface.source_map_ref },
        .{ .role = .elaboration_effect_row, .ref = forged_static_refs_surface.effect_row_ref },
        .{ .role = .elaboration_trace_map, .ref = trace_map_ref },
        .{ .role = .world_surface, .ref = forged_static_refs_surface.evidenceRef() },
        .{ .role = .world_port_table, .ref = port_table.evidenceRef() },
        .{ .role = .world_value_table, .ref = value_table.evidenceRef() },
        .{ .role = .world_dispatch_table, .ref = dispatch_table.evidenceRef() },
        .{ .role = .surface_profile, .ref = profile.evidenceRef() },
        .{ .role = .replay_key_recipe, .ref = forged_static_refs_replay.evidenceRef() },
        .{ .role = .residual_program, .ref = residual_program_ref },
    };
    const forged_static_refs_evidence_map = Elaboration.TargetEvidenceMap.init("target.forged-static-refs-evidence", forged_static_refs_dependencies[0..]);
    const forged_static_refs_certificate = Elaboration.Target.Certificate.init(.{
        .target_label = "target.forged-static-refs",
        .policy = policy,
        .elaboration_certificate_ref = forged_static_refs_elaboration_certificate_ref,
        .residual_program_ref = residual_program_ref,
        .world_surface_ref = forged_static_refs_surface.evidenceRef(),
        .port_table_ref = port_table.evidenceRef(),
        .value_table_ref = value_table.evidenceRef(),
        .dispatch_table_ref = dispatch_table.evidenceRef(),
        .profile_ref = profile.evidenceRef(),
        .replay_key_recipe_ref = forged_static_refs_replay.evidenceRef(),
        .evidence_map_ref = forged_static_refs_evidence_map.evidenceRef(),
        .trace_map_ref = trace_map_ref,
        .dependencies = forged_static_refs_dependencies[0..],
    });
    try std.testing.expectEqual(
        error.BoundaryTargetCertificateMismatch,
        forged_static_refs_certificate.check(policy, forged_static_refs_elaboration_certificate, forged_static_refs_surface, source_map, effect_row, trace_map, normal_form, world_ports[0..], port_table, value_table, dispatch_table, profile, forged_static_refs_replay, forged_static_refs_evidence_map, normalization_certificate, normalization_trace, normalization_redexes[0..], normalization_rules[0..], static_plans[0..]),
    );

    const forged_effect_row = Elaboration.EffectRow.init(.{
        .label = "target.forged-effect-row",
        .source_program_ref = residual_program_ref,
        .residual_program_ref = residual_program_ref,
        .normal_form = .world_ports_only,
        .source_effect_shapes = 1,
        .world_ports = 1,
    });
    const forged_normal_form = Elaboration.NormalForm.init("target.forged-normal-form", .world_ports_only, closure_certificate_ref, forged_effect_row.evidenceRef(), 0);
    const forged_elaboration_certificate = Elaboration.Certificate.init(.{
        .elaborated_program_label = "target.forged-elaboration",
        .source_program_ref = residual_program_ref,
        .residual_program_ref = residual_program_ref,
        .closure_certificate_ref = closure_certificate_ref,
        .closure_graph_ref = closure_graph_ref,
        .closure_report_ref = closure_report_ref,
        .source_map_ref = source_map.evidenceRef(),
        .effect_row_ref = forged_effect_row.evidenceRef(),
        .trace_map_ref = trace_map_ref,
        .normal_form_ref = forged_normal_form.evidenceRef(),
        .policy = policy.toElaborationPolicy(),
        .normal_form = .world_ports_only,
        .selected_static_treaty_plan_refs = &.{static_plan.evidenceRef()},
        .world_port_refs = &.{world_port_ref},
        .residual_world_port_refs = &.{world_port_ref},
        .summary_counts = .{
            .root_effect_shapes = 1,
            .world_ports_emitted = 1,
        },
    });
    try std.testing.expectEqual(
        error.BoundaryTargetCertificateMismatch,
        certificate.check(policy, forged_elaboration_certificate, surface, source_map, effect_row, trace_map, normal_form, world_ports[0..], port_table, value_table, dispatch_table, profile, replay, evidence_map, normalization_certificate, normalization_trace, normalization_redexes[0..], normalization_rules[0..], static_plans[0..]),
    );

    const forged_strict_normal_form = Elaboration.NormalForm.init("target.forged-strict-normal-form", .strict_closed, closure_certificate_ref, effect_row.evidenceRef(), 0);
    const forged_normal_form_elaboration_certificate = Elaboration.Certificate.init(.{
        .elaborated_program_label = "target.forged-normal-form-elaboration",
        .source_program_ref = residual_program_ref,
        .residual_program_ref = residual_program_ref,
        .closure_certificate_ref = closure_certificate_ref,
        .closure_graph_ref = closure_graph_ref,
        .closure_report_ref = closure_report_ref,
        .source_map_ref = source_map.evidenceRef(),
        .effect_row_ref = effect_row.evidenceRef(),
        .trace_map_ref = trace_map_ref,
        .normal_form_ref = forged_strict_normal_form.evidenceRef(),
        .policy = policy.toElaborationPolicy(),
        .normal_form = .strict_closed,
        .selected_static_treaty_plan_refs = &.{static_plan.evidenceRef()},
        .world_port_refs = &.{world_port_ref},
        .residual_world_port_refs = &.{world_port_ref},
        .summary_counts = .{
            .root_effect_shapes = 1,
            .world_ports_emitted = 1,
        },
    });
    try std.testing.expectEqual(
        error.BoundaryTargetCertificateMismatch,
        certificate.check(policy, forged_normal_form_elaboration_certificate, surface, source_map, effect_row, trace_map, normal_form, world_ports[0..], port_table, value_table, dispatch_table, profile, replay, evidence_map, normalization_certificate, normalization_trace, normalization_redexes[0..], normalization_rules[0..], static_plans[0..]),
    );

    var forged_port_entries = [_]Elaboration.WorldPortTable.Entry{port_table.entries[0]};
    forged_port_entries[0].source_ref = Evidence.refFor(Evidence.domains.boundary_effect_shape, 0xC781_F0A6, .{ .label = "target.forged-source" });
    const forged_port_table = Elaboration.WorldPortTable.init("target.forged-source-ports", forged_port_entries[0..]);
    const forged_surface_scope = Elaboration.WorldSurface.init(.{
        .label = "target.forged-source-surface",
        .residual_program_label = surface.residual_program_label,
        .residual_program_ref = surface.residual_program_ref,
        .elaboration_certificate_ref = surface.elaboration_certificate_ref,
        .source_map_ref = source_map.evidenceRef(),
        .effect_row_ref = effect_row.evidenceRef(),
        .port_table_ref = forged_port_table.evidenceRef(),
        .value_table_ref = value_table.evidenceRef(),
        .dispatch_table_ref = dispatch_table.evidenceRef(),
        .profile_ref = profile.evidenceRef(),
        .replay_key_recipe_ref = replay.evidenceRef(),
        .normal_form = surface.normal_form,
        .world_port_count = surface.world_port_count,
    });
    const forged_replay = Elaboration.ReplayKeyRecipe.init("target.forged-source-replay", forged_surface_scope.replayScopeRef(), replay.components);
    const forged_surface = Elaboration.WorldSurface.init(.{
        .label = forged_surface_scope.label,
        .residual_program_label = forged_surface_scope.residual_program_label,
        .residual_program_ref = forged_surface_scope.residual_program_ref,
        .elaboration_certificate_ref = forged_surface_scope.elaboration_certificate_ref,
        .source_map_ref = forged_surface_scope.source_map_ref,
        .effect_row_ref = forged_surface_scope.effect_row_ref,
        .port_table_ref = forged_surface_scope.port_table_ref,
        .value_table_ref = forged_surface_scope.value_table_ref,
        .dispatch_table_ref = forged_surface_scope.dispatch_table_ref,
        .profile_ref = forged_surface_scope.profile_ref,
        .replay_key_recipe_ref = forged_replay.evidenceRef(),
        .normal_form = forged_surface_scope.normal_form,
        .world_port_count = forged_surface_scope.world_port_count,
    });
    const forged_dependencies = [_]Evidence.Dependency{
        .{ .role = .elaboration_certificate, .ref = elaboration_certificate_ref },
        .{ .role = .elaboration_source_map, .ref = source_map.evidenceRef() },
        .{ .role = .elaboration_effect_row, .ref = effect_row.evidenceRef() },
        .{ .role = .elaboration_trace_map, .ref = trace_map_ref },
        .{ .role = .world_surface, .ref = forged_surface.evidenceRef() },
        .{ .role = .world_port_table, .ref = forged_port_table.evidenceRef() },
        .{ .role = .world_value_table, .ref = value_table.evidenceRef() },
        .{ .role = .world_dispatch_table, .ref = dispatch_table.evidenceRef() },
        .{ .role = .surface_profile, .ref = profile.evidenceRef() },
        .{ .role = .replay_key_recipe, .ref = forged_replay.evidenceRef() },
        .{ .role = .residual_program, .ref = residual_program_ref },
    };
    const forged_evidence_map = Elaboration.TargetEvidenceMap.init("target.forged-source-evidence", forged_dependencies[0..]);
    const forged_certificate = Elaboration.Target.Certificate.init(.{
        .target_label = "target.forged-source",
        .policy = policy,
        .elaboration_certificate_ref = elaboration_certificate_ref,
        .residual_program_ref = residual_program_ref,
        .world_surface_ref = forged_surface.evidenceRef(),
        .port_table_ref = forged_port_table.evidenceRef(),
        .value_table_ref = value_table.evidenceRef(),
        .dispatch_table_ref = dispatch_table.evidenceRef(),
        .profile_ref = profile.evidenceRef(),
        .replay_key_recipe_ref = forged_replay.evidenceRef(),
        .evidence_map_ref = forged_evidence_map.evidenceRef(),
        .trace_map_ref = trace_map_ref,
        .dependencies = forged_dependencies[0..],
    });
    try std.testing.expectEqual(
        error.BoundaryTargetCertificateMismatch,
        forged_certificate.check(policy, elaboration_certificate, forged_surface, source_map, effect_row, trace_map, normal_form, world_ports[0..], forged_port_table, value_table, dispatch_table, profile, forged_replay, forged_evidence_map, normalization_certificate, normalization_trace, normalization_redexes[0..], normalization_rules[0..], static_plans[0..]),
    );
    const stale_conformance_replay = Elaboration.ReplayKeyRecipe.init("target.stale-conformance-replay", surface.replayScopeRef(), replay.components);
    try std.testing.expectEqual(
        error.BoundaryTargetConformanceMismatch,
        Elaboration.Target.Conformance.check(surface, port_table, value_table, dispatch_table, profile, stale_conformance_replay),
    );
    var tampered_port_entries = [_]Elaboration.WorldPortTable.Entry{port_table.entries[0]};
    tampered_port_entries[0].protocol_label = "tampered";
    var tampered_port_table = port_table;
    tampered_port_table.entries = tampered_port_entries[0..];
    try std.testing.expectEqual(
        error.BoundaryTargetConformanceMismatch,
        Elaboration.Target.Conformance.check(surface, tampered_port_table, value_table, dispatch_table, profile, replay),
    );

    var forged_schema_entries = [_]Elaboration.WorldPortTable.Entry{port_table.entries[0]};
    forged_schema_entries[0].semantic_label = "forged.semantic-label";
    const forged_schema_port_table = Elaboration.WorldPortTable.init("target.forged-schema-ports", forged_schema_entries[0..]);
    const forged_schema_surface_scope = Elaboration.WorldSurface.init(.{
        .label = "target.forged-schema-surface",
        .residual_program_label = surface.residual_program_label,
        .residual_program_ref = surface.residual_program_ref,
        .elaboration_certificate_ref = surface.elaboration_certificate_ref,
        .source_map_ref = source_map.evidenceRef(),
        .effect_row_ref = effect_row.evidenceRef(),
        .port_table_ref = forged_schema_port_table.evidenceRef(),
        .value_table_ref = value_table.evidenceRef(),
        .dispatch_table_ref = dispatch_table.evidenceRef(),
        .profile_ref = profile.evidenceRef(),
        .replay_key_recipe_ref = replay.evidenceRef(),
        .normal_form = surface.normal_form,
        .world_port_count = surface.world_port_count,
    });
    const forged_schema_replay = Elaboration.ReplayKeyRecipe.init("target.forged-schema-replay", forged_schema_surface_scope.replayScopeRef(), replay.components);
    const forged_schema_surface = Elaboration.WorldSurface.init(.{
        .label = forged_schema_surface_scope.label,
        .residual_program_label = forged_schema_surface_scope.residual_program_label,
        .residual_program_ref = forged_schema_surface_scope.residual_program_ref,
        .elaboration_certificate_ref = forged_schema_surface_scope.elaboration_certificate_ref,
        .source_map_ref = forged_schema_surface_scope.source_map_ref,
        .effect_row_ref = forged_schema_surface_scope.effect_row_ref,
        .port_table_ref = forged_schema_surface_scope.port_table_ref,
        .value_table_ref = forged_schema_surface_scope.value_table_ref,
        .dispatch_table_ref = forged_schema_surface_scope.dispatch_table_ref,
        .profile_ref = forged_schema_surface_scope.profile_ref,
        .replay_key_recipe_ref = forged_schema_replay.evidenceRef(),
        .normal_form = forged_schema_surface_scope.normal_form,
        .world_port_count = forged_schema_surface_scope.world_port_count,
    });
    const forged_schema_dependencies = [_]Evidence.Dependency{
        .{ .role = .elaboration_certificate, .ref = elaboration_certificate_ref },
        .{ .role = .elaboration_source_map, .ref = source_map.evidenceRef() },
        .{ .role = .elaboration_effect_row, .ref = effect_row.evidenceRef() },
        .{ .role = .elaboration_trace_map, .ref = trace_map_ref },
        .{ .role = .world_surface, .ref = forged_schema_surface.evidenceRef() },
        .{ .role = .world_port_table, .ref = forged_schema_port_table.evidenceRef() },
        .{ .role = .world_value_table, .ref = value_table.evidenceRef() },
        .{ .role = .world_dispatch_table, .ref = dispatch_table.evidenceRef() },
        .{ .role = .surface_profile, .ref = profile.evidenceRef() },
        .{ .role = .replay_key_recipe, .ref = forged_schema_replay.evidenceRef() },
        .{ .role = .residual_program, .ref = residual_program_ref },
    };
    const forged_schema_evidence_map = Elaboration.TargetEvidenceMap.init("target.forged-schema-evidence", forged_schema_dependencies[0..]);
    const forged_schema_certificate = Elaboration.Target.Certificate.init(.{
        .target_label = "target.forged-schema",
        .policy = policy,
        .elaboration_certificate_ref = elaboration_certificate_ref,
        .residual_program_ref = residual_program_ref,
        .world_surface_ref = forged_schema_surface.evidenceRef(),
        .port_table_ref = forged_schema_port_table.evidenceRef(),
        .value_table_ref = value_table.evidenceRef(),
        .dispatch_table_ref = dispatch_table.evidenceRef(),
        .profile_ref = profile.evidenceRef(),
        .replay_key_recipe_ref = forged_schema_replay.evidenceRef(),
        .evidence_map_ref = forged_schema_evidence_map.evidenceRef(),
        .trace_map_ref = trace_map_ref,
        .dependencies = forged_schema_dependencies[0..],
    });
    try std.testing.expectEqual(
        error.BoundaryTargetCertificateMismatch,
        forged_schema_certificate.check(policy, elaboration_certificate, forged_schema_surface, source_map, effect_row, trace_map, normal_form, world_ports[0..], forged_schema_port_table, value_table, dispatch_table, profile, forged_schema_replay, forged_schema_evidence_map, normalization_certificate, normalization_trace, normalization_redexes[0..], normalization_rules[0..], static_plans[0..]),
    );

    const malformed_replay = Elaboration.ReplayKeyRecipe.init("target.malformed-replay", surface_scope.replayScopeRef(), &.{ "world_port_id", "world_surface_scope_fingerprint", "request_fingerprint" });
    const malformed_surface = Elaboration.WorldSurface.init(.{
        .label = surface_scope.label,
        .residual_program_label = surface_scope.residual_program_label,
        .residual_program_ref = surface_scope.residual_program_ref,
        .elaboration_certificate_ref = surface_scope.elaboration_certificate_ref,
        .source_map_ref = surface_scope.source_map_ref,
        .effect_row_ref = surface_scope.effect_row_ref,
        .port_table_ref = surface_scope.port_table_ref,
        .value_table_ref = surface_scope.value_table_ref,
        .dispatch_table_ref = surface_scope.dispatch_table_ref,
        .profile_ref = surface_scope.profile_ref,
        .replay_key_recipe_ref = malformed_replay.evidenceRef(),
        .normal_form = surface_scope.normal_form,
        .world_port_count = surface_scope.world_port_count,
    });
    const malformed_dependencies = [_]Evidence.Dependency{
        .{ .role = .elaboration_certificate, .ref = elaboration_certificate_ref },
        .{ .role = .elaboration_source_map, .ref = surface.source_map_ref },
        .{ .role = .elaboration_effect_row, .ref = surface.effect_row_ref },
        .{ .role = .elaboration_trace_map, .ref = trace_map_ref },
        .{ .role = .world_surface, .ref = malformed_surface.evidenceRef() },
        .{ .role = .world_port_table, .ref = port_table.evidenceRef() },
        .{ .role = .world_value_table, .ref = value_table.evidenceRef() },
        .{ .role = .world_dispatch_table, .ref = dispatch_table.evidenceRef() },
        .{ .role = .surface_profile, .ref = profile.evidenceRef() },
        .{ .role = .replay_key_recipe, .ref = malformed_replay.evidenceRef() },
        .{ .role = .residual_program, .ref = residual_program_ref },
    };
    const malformed_evidence_map = Elaboration.TargetEvidenceMap.init("target.malformed-replay-evidence", malformed_dependencies[0..]);
    const malformed_certificate = Elaboration.Target.Certificate.init(.{
        .target_label = "target.malformed-replay",
        .policy = policy,
        .elaboration_certificate_ref = elaboration_certificate_ref,
        .residual_program_ref = residual_program_ref,
        .world_surface_ref = malformed_surface.evidenceRef(),
        .port_table_ref = port_table.evidenceRef(),
        .value_table_ref = value_table.evidenceRef(),
        .dispatch_table_ref = dispatch_table.evidenceRef(),
        .profile_ref = profile.evidenceRef(),
        .replay_key_recipe_ref = malformed_replay.evidenceRef(),
        .evidence_map_ref = malformed_evidence_map.evidenceRef(),
        .trace_map_ref = trace_map_ref,
        .dependencies = malformed_dependencies[0..],
    });
    try std.testing.expectEqual(
        error.BoundaryTargetCertificateMismatch,
        malformed_certificate.check(policy, elaboration_certificate, malformed_surface, source_map, effect_row, trace_map, normal_form, world_ports[0..], port_table, value_table, dispatch_table, profile, malformed_replay, malformed_evidence_map, normalization_certificate, normalization_trace, normalization_redexes[0..], normalization_rules[0..], static_plans[0..]),
    );

    const zero_port_value_table = Elaboration.WorldValueTable.init("target.zero-port-values", value_entries[0..1]);
    const zero_port_profile = Elaboration.SurfaceProfile.init(.{
        .label = "target.zero-port-profile",
        .world_port_count = 0,
        .value_descriptor_count = zero_port_value_table.entries.len,
        .dispatch_entry_count = 0,
        .no_search_hot_path = true,
        .bounded = true,
    });
    const zero_port_table = Elaboration.WorldPortTable.init("target.zero-port-ports", &.{});
    const zero_port_dispatch_table = Elaboration.WorldDispatchTable.init("target.zero-port-dispatch", &.{});
    const zero_port_surface_scope = Elaboration.WorldSurface.init(.{
        .label = "target.zero-port-surface",
        .residual_program_label = "residual",
        .residual_program_ref = residual_program_ref,
        .elaboration_certificate_ref = elaboration_certificate_ref,
        .source_map_ref = source_map.evidenceRef(),
        .effect_row_ref = effect_row.evidenceRef(),
        .port_table_ref = zero_port_table.evidenceRef(),
        .value_table_ref = zero_port_value_table.evidenceRef(),
        .dispatch_table_ref = zero_port_dispatch_table.evidenceRef(),
        .profile_ref = zero_port_profile.evidenceRef(),
        .replay_key_recipe_ref = replay.evidenceRef(),
        .normal_form = .strict_closed,
        .world_port_count = 0,
    });
    const zero_port_replay = Elaboration.ReplayKeyRecipe.init("target.zero-port-replay", zero_port_surface_scope.replayScopeRef(), replay.components);
    const zero_port_surface = Elaboration.WorldSurface.init(.{
        .label = zero_port_surface_scope.label,
        .residual_program_label = zero_port_surface_scope.residual_program_label,
        .residual_program_ref = zero_port_surface_scope.residual_program_ref,
        .elaboration_certificate_ref = zero_port_surface_scope.elaboration_certificate_ref,
        .source_map_ref = zero_port_surface_scope.source_map_ref,
        .effect_row_ref = zero_port_surface_scope.effect_row_ref,
        .port_table_ref = zero_port_surface_scope.port_table_ref,
        .value_table_ref = zero_port_surface_scope.value_table_ref,
        .dispatch_table_ref = zero_port_surface_scope.dispatch_table_ref,
        .profile_ref = zero_port_surface_scope.profile_ref,
        .replay_key_recipe_ref = zero_port_replay.evidenceRef(),
        .normal_form = zero_port_surface_scope.normal_form,
        .world_port_count = zero_port_surface_scope.world_port_count,
    });
    const zero_port_dependencies = [_]Evidence.Dependency{
        .{ .role = .elaboration_certificate, .ref = elaboration_certificate_ref },
        .{ .role = .elaboration_source_map, .ref = source_map.evidenceRef() },
        .{ .role = .elaboration_effect_row, .ref = effect_row.evidenceRef() },
        .{ .role = .elaboration_trace_map, .ref = trace_map_ref },
        .{ .role = .world_surface, .ref = zero_port_surface.evidenceRef() },
        .{ .role = .world_port_table, .ref = zero_port_table.evidenceRef() },
        .{ .role = .world_value_table, .ref = zero_port_value_table.evidenceRef() },
        .{ .role = .world_dispatch_table, .ref = zero_port_dispatch_table.evidenceRef() },
        .{ .role = .surface_profile, .ref = zero_port_profile.evidenceRef() },
        .{ .role = .replay_key_recipe, .ref = zero_port_replay.evidenceRef() },
        .{ .role = .residual_program, .ref = residual_program_ref },
    };
    const zero_port_evidence_map = Elaboration.TargetEvidenceMap.init("target.zero-port-evidence", zero_port_dependencies[0..]);
    const zero_port_certificate = Elaboration.Target.Certificate.init(.{
        .target_label = "target.zero-port",
        .policy = policy,
        .elaboration_certificate_ref = elaboration_certificate_ref,
        .residual_program_ref = residual_program_ref,
        .world_surface_ref = zero_port_surface.evidenceRef(),
        .port_table_ref = zero_port_table.evidenceRef(),
        .value_table_ref = zero_port_value_table.evidenceRef(),
        .dispatch_table_ref = zero_port_dispatch_table.evidenceRef(),
        .profile_ref = zero_port_profile.evidenceRef(),
        .replay_key_recipe_ref = zero_port_replay.evidenceRef(),
        .evidence_map_ref = zero_port_evidence_map.evidenceRef(),
        .trace_map_ref = trace_map_ref,
        .dependencies = zero_port_dependencies[0..],
    });
    try std.testing.expectEqual(
        error.BoundaryTargetCertificateMismatch,
        zero_port_certificate.check(policy, elaboration_certificate, zero_port_surface, source_map, effect_row, trace_map, normal_form, world_ports[0..], zero_port_table, zero_port_value_table, zero_port_dispatch_table, zero_port_profile, zero_port_replay, zero_port_evidence_map, normalization_certificate, normalization_trace, normalization_redexes[0..], normalization_rules[0..], static_plans[0..]),
    );

    const gapped_port_entries = [_]Elaboration.WorldPortTable.Entry{.{
        .world_port_id = 0,
        .residual_site_index = 5,
        .residual_site_fingerprint = 0xC781_0005,
        .world_port_ref = world_port_ref,
        .source_ref = source_ref,
        .payload_ref = value_ref,
        .resume_ref = value_ref,
        .result_ref = value_ref,
        .protocol_label = "approval",
        .op_name = "request",
        .mode = "transform",
        .semantic_label = "approval.request",
    }};
    const gapped_port_table = Elaboration.WorldPortTable.init("target.gapped-ports", gapped_port_entries[0..]);
    const gapped_source_entries = [_]Elaboration.SourceMap.Entry{.{
        .source_ref = source_ref,
        .residual_ref = residual_program_ref,
        .source_site_index = 0,
        .residual_site_index = 5,
        .static_treaty_plan_ref = static_plan.evidenceRef(),
        .world_port_ref = world_port_ref,
        .disposition = .world_port_lowered,
        .label = "target.gapped-source-entry",
    }};
    const gapped_source_map = Elaboration.SourceMap.init("target.gapped-source-map", gapped_source_entries[0..], &.{});
    const gapped_normalization_redex = Elaboration.Target.Normalization.Redex.init(.{
        .label = "target.gapped-source-entry",
        .source_effect_shape_ref = source_ref,
        .coordinates = .{ .function_index = 0, .block_index = 0, .instruction_index = 0, .site_index = 0 },
        .kind = .world_port_site,
        .selected_static_treaty_plan_ref = static_plan.evidenceRef(),
        .current_program_plan_ref = residual_program_ref,
        .semantic_body = .declarative,
        .expected_lowering_kind = .residual_world_port,
        .evidence_dependencies = normalization_redex_dependencies[0..],
    });
    const gapped_normalization_rule = Elaboration.Target.Normalization.RewriteRule.init(.{
        .label = "target.gapped-source-entry",
        .kind = .residual_world_port,
        .evidence_dependencies = normalization_rule_dependencies[0..],
        .produced_source_map_entries = 1,
        .produced_trace_map_entries = 1,
        .produced_effect_row_entries = 1,
    });
    const gapped_route_lowering_fingerprint = Evidence.boundaryNormalizationRouteLoweringFingerprint(gapped_source_entries[0], residual_program_ref.fingerprint);
    const gapped_normalization_step = Elaboration.Target.Normalization.RewriteStep.init(.{
        .step_index = 0,
        .redex_ref = gapped_normalization_redex.evidenceRef(),
        .rewrite_rule_ref = gapped_normalization_rule.evidenceRef(),
        .selected_static_treaty_plan_ref = static_plan.evidenceRef(),
        .source_effect_shape_ref = source_ref,
        .input_program_plan_hash = residual_program_ref.fingerprint,
        .output_program_plan_hash = residual_program_ref.fingerprint,
        .builder_state_fingerprint = gapped_route_lowering_fingerprint,
        .world_port_ref = world_port_ref,
        .summary = "residual_world_port",
    });
    const gapped_normalization_redexes = [_]Elaboration.Target.Normalization.Redex{gapped_normalization_redex};
    const gapped_normalization_rules = [_]Elaboration.Target.Normalization.RewriteRule{gapped_normalization_rule};
    const gapped_normalization_steps = [_]Elaboration.Target.Normalization.RewriteStep{gapped_normalization_step};
    const gapped_trace_entries = [_]Elaboration.TraceMap.Entry{.{
        .source_ref = source_ref,
        .residual_ref = world_port_ref,
        .trace_label = "target.gapped-source-entry",
    }};
    const gapped_trace_map = Elaboration.TraceMap.init("target.gapped-trace-map", gapped_trace_entries[0..]);
    const gapped_effect_row = Elaboration.EffectRow.init(.{
        .label = "target.gapped-effect-row",
        .source_program_ref = residual_program_ref,
        .residual_program_ref = residual_program_ref,
        .normal_form = .world_ports_only,
        .source_effect_shapes = 1,
        .world_ports = 1,
    });
    const gapped_normal_form = Elaboration.NormalForm.init("target.gapped-normal-form", .world_ports_only, closure_certificate_ref, gapped_effect_row.evidenceRef(), 0);
    const gapped_elaboration_certificate = Elaboration.Certificate.init(.{
        .elaborated_program_label = "target.gapped-elaboration",
        .source_program_ref = residual_program_ref,
        .residual_program_ref = residual_program_ref,
        .closure_certificate_ref = closure_certificate_ref,
        .closure_graph_ref = closure_graph_ref,
        .closure_report_ref = closure_report_ref,
        .source_map_ref = gapped_source_map.evidenceRef(),
        .effect_row_ref = gapped_effect_row.evidenceRef(),
        .trace_map_ref = gapped_trace_map.evidenceRef(),
        .normal_form_ref = gapped_normal_form.evidenceRef(),
        .policy = policy.toElaborationPolicy(),
        .normal_form = .world_ports_only,
        .selected_static_treaty_plan_refs = &.{static_plan.evidenceRef()},
        .world_port_refs = &.{world_port_ref},
        .residual_world_port_refs = &.{world_port_ref},
        .summary_counts = .{
            .root_effect_shapes = 1,
            .world_ports_emitted = 1,
        },
    });
    const gapped_elaboration_certificate_ref = gapped_elaboration_certificate.evidenceRef();
    const gapped_dispatch_entries = [_]Elaboration.WorldDispatchTable.Entry{
        .{ .residual_site_index = 0, .residual_site_fingerprint = 0, .world_port_id = Elaboration.WorldDispatchTable.missing_world_port_id },
        .{ .residual_site_index = 1, .residual_site_fingerprint = 0, .world_port_id = Elaboration.WorldDispatchTable.missing_world_port_id },
        .{ .residual_site_index = 2, .residual_site_fingerprint = 0, .world_port_id = Elaboration.WorldDispatchTable.missing_world_port_id },
        .{ .residual_site_index = 3, .residual_site_fingerprint = 0, .world_port_id = Elaboration.WorldDispatchTable.missing_world_port_id },
        .{ .residual_site_index = 4, .residual_site_fingerprint = 0, .world_port_id = Elaboration.WorldDispatchTable.missing_world_port_id },
        .{ .residual_site_index = 5, .residual_site_fingerprint = 0xC781_0005, .world_port_id = 0 },
    };
    const gapped_dispatch_table = Elaboration.WorldDispatchTable.init("target.gapped-dispatch", gapped_dispatch_entries[0..]);
    const gapped_profile = Elaboration.SurfaceProfile.init(.{
        .label = "target.gapped-profile",
        .world_port_count = gapped_port_table.entries.len,
        .value_descriptor_count = value_table.entries.len,
        .dispatch_entry_count = gapped_dispatch_table.entries.len,
        .no_search_hot_path = true,
        .bounded = true,
    });
    const gapped_surface_scope = Elaboration.WorldSurface.init(.{
        .label = "target.gapped-surface",
        .residual_program_label = "residual",
        .residual_program_ref = residual_program_ref,
        .elaboration_certificate_ref = gapped_elaboration_certificate_ref,
        .source_map_ref = gapped_source_map.evidenceRef(),
        .effect_row_ref = gapped_effect_row.evidenceRef(),
        .port_table_ref = gapped_port_table.evidenceRef(),
        .value_table_ref = value_table.evidenceRef(),
        .dispatch_table_ref = gapped_dispatch_table.evidenceRef(),
        .profile_ref = gapped_profile.evidenceRef(),
        .replay_key_recipe_ref = replay.evidenceRef(),
        .normal_form = .world_ports_only,
        .world_port_count = 1,
    });
    const gapped_replay = Elaboration.ReplayKeyRecipe.init("target.gapped-replay", gapped_surface_scope.replayScopeRef(), replay.components);
    const gapped_surface = Elaboration.WorldSurface.init(.{
        .label = gapped_surface_scope.label,
        .residual_program_label = gapped_surface_scope.residual_program_label,
        .residual_program_ref = gapped_surface_scope.residual_program_ref,
        .elaboration_certificate_ref = gapped_surface_scope.elaboration_certificate_ref,
        .source_map_ref = gapped_surface_scope.source_map_ref,
        .effect_row_ref = gapped_surface_scope.effect_row_ref,
        .port_table_ref = gapped_surface_scope.port_table_ref,
        .value_table_ref = gapped_surface_scope.value_table_ref,
        .dispatch_table_ref = gapped_surface_scope.dispatch_table_ref,
        .profile_ref = gapped_surface_scope.profile_ref,
        .replay_key_recipe_ref = gapped_replay.evidenceRef(),
        .normal_form = gapped_surface_scope.normal_form,
        .world_port_count = gapped_surface_scope.world_port_count,
    });
    const gapped_dependencies = [_]Evidence.Dependency{
        .{ .role = .elaboration_certificate, .ref = gapped_elaboration_certificate_ref },
        .{ .role = .elaboration_source_map, .ref = gapped_source_map.evidenceRef() },
        .{ .role = .elaboration_effect_row, .ref = gapped_effect_row.evidenceRef() },
        .{ .role = .elaboration_trace_map, .ref = gapped_trace_map.evidenceRef() },
        .{ .role = .world_surface, .ref = gapped_surface.evidenceRef() },
        .{ .role = .world_port_table, .ref = gapped_port_table.evidenceRef() },
        .{ .role = .world_value_table, .ref = value_table.evidenceRef() },
        .{ .role = .world_dispatch_table, .ref = gapped_dispatch_table.evidenceRef() },
        .{ .role = .surface_profile, .ref = gapped_profile.evidenceRef() },
        .{ .role = .replay_key_recipe, .ref = gapped_replay.evidenceRef() },
        .{ .role = .residual_program, .ref = residual_program_ref },
    };
    const gapped_evidence_map = Elaboration.TargetEvidenceMap.init("target.gapped-evidence", gapped_dependencies[0..]);
    const gapped_normalization_trace_dependencies = [_]Evidence.Dependency{
        .{ .role = .closure_certificate, .ref = closure_certificate_ref },
        .{ .role = .residual_program, .ref = residual_program_ref },
        .{ .role = .elaboration_source_map, .ref = gapped_source_map.evidenceRef() },
        .{ .role = .elaboration_effect_row, .ref = gapped_effect_row.evidenceRef() },
        .{ .role = .normal_form, .ref = gapped_normal_form.evidenceRef() },
    };
    const gapped_normalization_trace = Elaboration.Target.Normalization.Trace.init(.{
        .label = "target.gapped-normalization.trace",
        .root_program_ref = residual_program_ref,
        .closure_certificate_ref = closure_certificate_ref,
        .rewrite_steps = gapped_normalization_steps[0..],
        .residual_world_port_refs = normalization_world_ports[0..],
        .final_program_plan_hash = residual_program_ref.fingerprint,
        .final_normal_form = .world_ports_only,
        .evidence_dependencies = gapped_normalization_trace_dependencies[0..],
    });
    const gapped_normalization_certificate_dependencies = [_]Evidence.Dependency{
        .{ .role = .normalization_trace, .ref = gapped_normalization_trace.evidenceRef() },
        .{ .role = .elaboration_source_map, .ref = gapped_source_map.evidenceRef() },
        .{ .role = .elaboration_trace_map, .ref = gapped_trace_map.evidenceRef() },
        .{ .role = .target_evidence_map, .ref = gapped_evidence_map.evidenceRef() },
        .{ .role = .elaboration_effect_row, .ref = gapped_effect_row.evidenceRef() },
        .{ .role = .normal_form, .ref = gapped_normal_form.evidenceRef() },
        .{ .role = .world_surface, .ref = gapped_surface.evidenceRef() },
    };
    const gapped_normalization_certificate = Elaboration.Target.Normalization.Certificate.init(.{
        .label = "target.gapped-normalization.certificate",
        .closure_certificate_ref = closure_certificate_ref,
        .target_policy_fingerprint = policy.fingerprint(),
        .normalization_trace_ref = gapped_normalization_trace.evidenceRef(),
        .final_program_plan_hash = residual_program_ref.fingerprint,
        .source_map_ref = gapped_source_map.evidenceRef(),
        .trace_map_ref = gapped_trace_map.evidenceRef(),
        .evidence_map_ref = gapped_evidence_map.evidenceRef(),
        .effect_row_ref = gapped_effect_row.evidenceRef(),
        .normal_form_ref = gapped_normal_form.evidenceRef(),
        .world_surface_ref = gapped_surface.evidenceRef(),
        .dependencies = gapped_normalization_certificate_dependencies[0..],
    });
    const gapped_certificate_dependencies = gapped_dependencies ++ [_]Evidence.Dependency{
        .{ .role = .normalization_certificate, .ref = gapped_normalization_certificate.evidenceRef() },
    };
    const gapped_certificate = Elaboration.Target.Certificate.init(.{
        .target_label = "target.gapped",
        .policy = policy,
        .elaboration_certificate_ref = gapped_elaboration_certificate_ref,
        .residual_program_ref = residual_program_ref,
        .world_surface_ref = gapped_surface.evidenceRef(),
        .port_table_ref = gapped_port_table.evidenceRef(),
        .value_table_ref = value_table.evidenceRef(),
        .dispatch_table_ref = gapped_dispatch_table.evidenceRef(),
        .profile_ref = gapped_profile.evidenceRef(),
        .replay_key_recipe_ref = gapped_replay.evidenceRef(),
        .evidence_map_ref = gapped_evidence_map.evidenceRef(),
        .trace_map_ref = gapped_trace_map.evidenceRef(),
        .normalization_certificate_ref = gapped_normalization_certificate.evidenceRef(),
        .dependencies = gapped_certificate_dependencies[0..],
    });
    try gapped_certificate.check(policy, gapped_elaboration_certificate, gapped_surface, gapped_source_map, gapped_effect_row, gapped_trace_map, gapped_normal_form, world_ports[0..], gapped_port_table, value_table, gapped_dispatch_table, gapped_profile, gapped_replay, gapped_evidence_map, gapped_normalization_certificate, gapped_normalization_trace, gapped_normalization_redexes[0..], gapped_normalization_rules[0..], static_plans[0..]);
    try std.testing.expectEqual(null, gapped_dispatch_table.lookup(0));
    try std.testing.expectEqual(@as(u32, 0), gapped_dispatch_table.lookup(5).?);

    var bounded_gapped_policy = policy;
    bounded_gapped_policy.require_bounded_surface = true;
    bounded_gapped_policy.max_world_ports = 1;
    bounded_gapped_policy.max_value_descriptors = 3;
    bounded_gapped_policy.max_dispatch_entries = 1;
    const bounded_gapped_normalization_certificate = Elaboration.Target.Normalization.Certificate.init(.{
        .label = "target.gapped-bounded-normalization.certificate",
        .closure_certificate_ref = closure_certificate_ref,
        .target_policy_fingerprint = bounded_gapped_policy.fingerprint(),
        .normalization_trace_ref = gapped_normalization_trace.evidenceRef(),
        .final_program_plan_hash = residual_program_ref.fingerprint,
        .source_map_ref = gapped_source_map.evidenceRef(),
        .trace_map_ref = gapped_trace_map.evidenceRef(),
        .evidence_map_ref = gapped_evidence_map.evidenceRef(),
        .effect_row_ref = gapped_effect_row.evidenceRef(),
        .normal_form_ref = gapped_normal_form.evidenceRef(),
        .world_surface_ref = gapped_surface.evidenceRef(),
        .dependencies = (&[_]Evidence.Dependency{
            .{ .role = .normalization_trace, .ref = gapped_normalization_trace.evidenceRef() },
            .{ .role = .elaboration_source_map, .ref = gapped_source_map.evidenceRef() },
            .{ .role = .elaboration_trace_map, .ref = gapped_trace_map.evidenceRef() },
            .{ .role = .target_evidence_map, .ref = gapped_evidence_map.evidenceRef() },
            .{ .role = .elaboration_effect_row, .ref = gapped_effect_row.evidenceRef() },
            .{ .role = .normal_form, .ref = gapped_normal_form.evidenceRef() },
            .{ .role = .world_surface, .ref = gapped_surface.evidenceRef() },
        })[0..],
    });
    const bounded_gapped_certificate_dependencies = gapped_dependencies ++ [_]Evidence.Dependency{
        .{ .role = .normalization_certificate, .ref = bounded_gapped_normalization_certificate.evidenceRef() },
    };
    const bounded_gapped_certificate = Elaboration.Target.Certificate.init(.{
        .target_label = "target.gapped",
        .policy = bounded_gapped_policy,
        .elaboration_certificate_ref = gapped_elaboration_certificate_ref,
        .residual_program_ref = residual_program_ref,
        .world_surface_ref = gapped_surface.evidenceRef(),
        .port_table_ref = gapped_port_table.evidenceRef(),
        .value_table_ref = value_table.evidenceRef(),
        .dispatch_table_ref = gapped_dispatch_table.evidenceRef(),
        .profile_ref = gapped_profile.evidenceRef(),
        .replay_key_recipe_ref = gapped_replay.evidenceRef(),
        .evidence_map_ref = gapped_evidence_map.evidenceRef(),
        .trace_map_ref = gapped_trace_map.evidenceRef(),
        .normalization_certificate_ref = bounded_gapped_normalization_certificate.evidenceRef(),
        .dependencies = bounded_gapped_certificate_dependencies[0..],
    });
    try std.testing.expectEqual(
        error.BoundaryTargetCertificateMismatch,
        bounded_gapped_certificate.check(bounded_gapped_policy, gapped_elaboration_certificate, gapped_surface, gapped_source_map, gapped_effect_row, gapped_trace_map, gapped_normal_form, world_ports[0..], gapped_port_table, value_table, gapped_dispatch_table, gapped_profile, gapped_replay, gapped_evidence_map, bounded_gapped_normalization_certificate, gapped_normalization_trace, gapped_normalization_redexes[0..], gapped_normalization_rules[0..], static_plans[0..]),
    );

    const unbounded_gapped_profile = Elaboration.SurfaceProfile.init(.{
        .label = "target.gapped-unbounded-profile",
        .world_port_count = gapped_port_table.entries.len,
        .value_descriptor_count = value_table.entries.len,
        .dispatch_entry_count = gapped_dispatch_table.entries.len,
        .no_search_hot_path = true,
        .bounded = false,
    });
    const unbounded_gapped_surface_scope = Elaboration.WorldSurface.init(.{
        .label = "target.gapped-unbounded-surface",
        .residual_program_label = "residual",
        .residual_program_ref = residual_program_ref,
        .elaboration_certificate_ref = gapped_elaboration_certificate_ref,
        .source_map_ref = gapped_source_map.evidenceRef(),
        .effect_row_ref = gapped_effect_row.evidenceRef(),
        .port_table_ref = gapped_port_table.evidenceRef(),
        .value_table_ref = value_table.evidenceRef(),
        .dispatch_table_ref = gapped_dispatch_table.evidenceRef(),
        .profile_ref = unbounded_gapped_profile.evidenceRef(),
        .replay_key_recipe_ref = replay.evidenceRef(),
        .normal_form = .world_ports_only,
        .world_port_count = 1,
    });
    const unbounded_gapped_replay = Elaboration.ReplayKeyRecipe.init("target.gapped-unbounded-replay", unbounded_gapped_surface_scope.replayScopeRef(), replay.components);
    const unbounded_gapped_surface = Elaboration.WorldSurface.init(.{
        .label = unbounded_gapped_surface_scope.label,
        .residual_program_label = unbounded_gapped_surface_scope.residual_program_label,
        .residual_program_ref = unbounded_gapped_surface_scope.residual_program_ref,
        .elaboration_certificate_ref = unbounded_gapped_surface_scope.elaboration_certificate_ref,
        .source_map_ref = unbounded_gapped_surface_scope.source_map_ref,
        .effect_row_ref = unbounded_gapped_surface_scope.effect_row_ref,
        .port_table_ref = unbounded_gapped_surface_scope.port_table_ref,
        .value_table_ref = unbounded_gapped_surface_scope.value_table_ref,
        .dispatch_table_ref = unbounded_gapped_surface_scope.dispatch_table_ref,
        .profile_ref = unbounded_gapped_surface_scope.profile_ref,
        .replay_key_recipe_ref = unbounded_gapped_replay.evidenceRef(),
        .normal_form = unbounded_gapped_surface_scope.normal_form,
        .world_port_count = unbounded_gapped_surface_scope.world_port_count,
    });
    const unbounded_gapped_dependencies = [_]Evidence.Dependency{
        .{ .role = .elaboration_certificate, .ref = gapped_elaboration_certificate_ref },
        .{ .role = .elaboration_source_map, .ref = gapped_source_map.evidenceRef() },
        .{ .role = .elaboration_effect_row, .ref = gapped_effect_row.evidenceRef() },
        .{ .role = .elaboration_trace_map, .ref = gapped_trace_map.evidenceRef() },
        .{ .role = .world_surface, .ref = unbounded_gapped_surface.evidenceRef() },
        .{ .role = .world_port_table, .ref = gapped_port_table.evidenceRef() },
        .{ .role = .world_value_table, .ref = value_table.evidenceRef() },
        .{ .role = .world_dispatch_table, .ref = gapped_dispatch_table.evidenceRef() },
        .{ .role = .surface_profile, .ref = unbounded_gapped_profile.evidenceRef() },
        .{ .role = .replay_key_recipe, .ref = unbounded_gapped_replay.evidenceRef() },
        .{ .role = .residual_program, .ref = residual_program_ref },
    };
    const unbounded_gapped_evidence_map = Elaboration.TargetEvidenceMap.init("target.gapped-unbounded-evidence", unbounded_gapped_dependencies[0..]);
    var unbounded_gapped_policy = policy;
    unbounded_gapped_policy.require_bounded_surface = false;
    unbounded_gapped_policy.fail_on_unbounded_world_port_when_bounded_required = false;
    unbounded_gapped_policy.max_world_ports = 1;
    unbounded_gapped_policy.max_value_descriptors = 3;
    unbounded_gapped_policy.max_dispatch_entries = 1;
    const unbounded_gapped_normalization_trace = Elaboration.Target.Normalization.Trace.init(.{
        .label = "target.gapped-unbounded-normalization.trace",
        .root_program_ref = residual_program_ref,
        .closure_certificate_ref = closure_certificate_ref,
        .rewrite_steps = gapped_normalization_steps[0..],
        .residual_world_port_refs = normalization_world_ports[0..],
        .final_program_plan_hash = residual_program_ref.fingerprint,
        .final_normal_form = .world_ports_only,
        .evidence_dependencies = gapped_normalization_trace_dependencies[0..],
    });
    const unbounded_gapped_normalization_certificate = Elaboration.Target.Normalization.Certificate.init(.{
        .label = "target.gapped-unbounded-normalization.certificate",
        .closure_certificate_ref = closure_certificate_ref,
        .target_policy_fingerprint = unbounded_gapped_policy.fingerprint(),
        .normalization_trace_ref = unbounded_gapped_normalization_trace.evidenceRef(),
        .final_program_plan_hash = residual_program_ref.fingerprint,
        .source_map_ref = gapped_source_map.evidenceRef(),
        .trace_map_ref = gapped_trace_map.evidenceRef(),
        .evidence_map_ref = unbounded_gapped_evidence_map.evidenceRef(),
        .effect_row_ref = gapped_effect_row.evidenceRef(),
        .normal_form_ref = gapped_normal_form.evidenceRef(),
        .world_surface_ref = unbounded_gapped_surface.evidenceRef(),
        .dependencies = (&[_]Evidence.Dependency{
            .{ .role = .normalization_trace, .ref = unbounded_gapped_normalization_trace.evidenceRef() },
            .{ .role = .elaboration_source_map, .ref = gapped_source_map.evidenceRef() },
            .{ .role = .elaboration_trace_map, .ref = gapped_trace_map.evidenceRef() },
            .{ .role = .target_evidence_map, .ref = unbounded_gapped_evidence_map.evidenceRef() },
            .{ .role = .elaboration_effect_row, .ref = gapped_effect_row.evidenceRef() },
            .{ .role = .normal_form, .ref = gapped_normal_form.evidenceRef() },
            .{ .role = .world_surface, .ref = unbounded_gapped_surface.evidenceRef() },
        })[0..],
    });
    const unbounded_gapped_certificate_dependencies = unbounded_gapped_dependencies ++ [_]Evidence.Dependency{
        .{ .role = .normalization_certificate, .ref = unbounded_gapped_normalization_certificate.evidenceRef() },
    };
    const unbounded_gapped_certificate = Elaboration.Target.Certificate.init(.{
        .target_label = "target.gapped-unbounded",
        .policy = unbounded_gapped_policy,
        .elaboration_certificate_ref = gapped_elaboration_certificate_ref,
        .residual_program_ref = residual_program_ref,
        .world_surface_ref = unbounded_gapped_surface.evidenceRef(),
        .port_table_ref = gapped_port_table.evidenceRef(),
        .value_table_ref = value_table.evidenceRef(),
        .dispatch_table_ref = gapped_dispatch_table.evidenceRef(),
        .profile_ref = unbounded_gapped_profile.evidenceRef(),
        .replay_key_recipe_ref = unbounded_gapped_replay.evidenceRef(),
        .evidence_map_ref = unbounded_gapped_evidence_map.evidenceRef(),
        .trace_map_ref = gapped_trace_map.evidenceRef(),
        .normalization_certificate_ref = unbounded_gapped_normalization_certificate.evidenceRef(),
        .dependencies = unbounded_gapped_certificate_dependencies[0..],
    });
    try unbounded_gapped_certificate.check(unbounded_gapped_policy, gapped_elaboration_certificate, unbounded_gapped_surface, gapped_source_map, gapped_effect_row, gapped_trace_map, gapped_normal_form, world_ports[0..], gapped_port_table, value_table, gapped_dispatch_table, unbounded_gapped_profile, unbounded_gapped_replay, unbounded_gapped_evidence_map, unbounded_gapped_normalization_certificate, unbounded_gapped_normalization_trace, gapped_normalization_redexes[0..], gapped_normalization_rules[0..], static_plans[0..]);

    var no_surface_policy = policy;
    no_surface_policy.emit_world_surface = false;
    const no_surface_certificate = Elaboration.Target.Certificate.init(.{
        .target_label = "target.no-surface",
        .policy = no_surface_policy,
        .elaboration_certificate_ref = elaboration_certificate_ref,
        .residual_program_ref = residual_program_ref,
        .world_surface_ref = surface.evidenceRef(),
        .port_table_ref = port_table.evidenceRef(),
        .value_table_ref = value_table.evidenceRef(),
        .dispatch_table_ref = dispatch_table.evidenceRef(),
        .profile_ref = profile.evidenceRef(),
        .replay_key_recipe_ref = replay.evidenceRef(),
        .evidence_map_ref = evidence_map.evidenceRef(),
        .trace_map_ref = trace_map_ref,
        .dependencies = dependencies[0..],
    });
    try std.testing.expectEqual(
        error.BoundaryTargetPolicyMismatch,
        no_surface_certificate.check(no_surface_policy, elaboration_certificate, surface, source_map, effect_row, trace_map, normal_form, world_ports[0..], port_table, value_table, dispatch_table, profile, replay, evidence_map, normalization_certificate, normalization_trace, normalization_redexes[0..], normalization_rules[0..], static_plans[0..]),
    );

    var unsupported_surface = surface;
    unsupported_surface.surface_format_version = surface.surface_format_version + 1;
    unsupported_surface.surface_fingerprint = unsupported_surface.computeFingerprint();
    const unsupported_dependencies = [_]Evidence.Dependency{
        .{ .role = .elaboration_certificate, .ref = elaboration_certificate_ref },
        .{ .role = .elaboration_source_map, .ref = surface.source_map_ref },
        .{ .role = .elaboration_effect_row, .ref = surface.effect_row_ref },
        .{ .role = .elaboration_trace_map, .ref = trace_map_ref },
        .{ .role = .world_surface, .ref = unsupported_surface.evidenceRef() },
        .{ .role = .world_port_table, .ref = port_table.evidenceRef() },
        .{ .role = .world_value_table, .ref = value_table.evidenceRef() },
        .{ .role = .world_dispatch_table, .ref = dispatch_table.evidenceRef() },
        .{ .role = .surface_profile, .ref = profile.evidenceRef() },
        .{ .role = .replay_key_recipe, .ref = replay.evidenceRef() },
        .{ .role = .residual_program, .ref = residual_program_ref },
    };
    const unsupported_evidence_map = Elaboration.TargetEvidenceMap.init("target.unsupported-evidence", unsupported_dependencies[0..]);
    const unsupported_certificate = Elaboration.Target.Certificate.init(.{
        .target_label = "target.unsupported",
        .policy = policy,
        .elaboration_certificate_ref = elaboration_certificate_ref,
        .residual_program_ref = residual_program_ref,
        .world_surface_ref = unsupported_surface.evidenceRef(),
        .port_table_ref = port_table.evidenceRef(),
        .value_table_ref = value_table.evidenceRef(),
        .dispatch_table_ref = dispatch_table.evidenceRef(),
        .profile_ref = profile.evidenceRef(),
        .replay_key_recipe_ref = replay.evidenceRef(),
        .evidence_map_ref = unsupported_evidence_map.evidenceRef(),
        .trace_map_ref = trace_map_ref,
        .dependencies = unsupported_dependencies[0..],
    });
    try std.testing.expectEqual(
        error.BoundaryTargetCertificateMismatch,
        unsupported_certificate.check(policy, elaboration_certificate, unsupported_surface, source_map, effect_row, trace_map, normal_form, world_ports[0..], port_table, value_table, dispatch_table, profile, replay, unsupported_evidence_map, normalization_certificate, normalization_trace, normalization_redexes[0..], normalization_rules[0..], static_plans[0..]),
    );
    try std.testing.expectEqual(
        error.BoundaryTargetConformanceMismatch,
        Elaboration.Target.Conformance.check(unsupported_surface, port_table, value_table, dispatch_table, profile, replay),
    );

    var wrong_source_surface_scope = surface;
    wrong_source_surface_scope.source_map_ref = Evidence.refFor(Evidence.domains.program_plan, 0xC781_00A0, .{ .label = "wrong-source-map-domain" });
    wrong_source_surface_scope.surface_fingerprint = wrong_source_surface_scope.computeFingerprint();
    const wrong_source_replay = Elaboration.ReplayKeyRecipe.init("target.wrong-source-replay", wrong_source_surface_scope.replayScopeRef(), replay.components);
    var wrong_source_surface = wrong_source_surface_scope;
    wrong_source_surface.replay_key_recipe_ref = wrong_source_replay.evidenceRef();
    wrong_source_surface.surface_fingerprint = wrong_source_surface.computeFingerprint();
    const wrong_source_dependencies = [_]Evidence.Dependency{
        .{ .role = .elaboration_certificate, .ref = elaboration_certificate_ref },
        .{ .role = .elaboration_source_map, .ref = surface.source_map_ref },
        .{ .role = .elaboration_effect_row, .ref = surface.effect_row_ref },
        .{ .role = .elaboration_trace_map, .ref = trace_map_ref },
        .{ .role = .world_surface, .ref = wrong_source_surface.evidenceRef() },
        .{ .role = .world_port_table, .ref = port_table.evidenceRef() },
        .{ .role = .world_value_table, .ref = value_table.evidenceRef() },
        .{ .role = .world_dispatch_table, .ref = dispatch_table.evidenceRef() },
        .{ .role = .surface_profile, .ref = profile.evidenceRef() },
        .{ .role = .replay_key_recipe, .ref = wrong_source_replay.evidenceRef() },
        .{ .role = .residual_program, .ref = residual_program_ref },
    };
    const wrong_source_evidence_map = Elaboration.TargetEvidenceMap.init("target.wrong-source-evidence", wrong_source_dependencies[0..]);
    const wrong_source_certificate = Elaboration.Target.Certificate.init(.{
        .target_label = "target.wrong-source",
        .policy = policy,
        .elaboration_certificate_ref = elaboration_certificate_ref,
        .residual_program_ref = residual_program_ref,
        .world_surface_ref = wrong_source_surface.evidenceRef(),
        .port_table_ref = port_table.evidenceRef(),
        .value_table_ref = value_table.evidenceRef(),
        .dispatch_table_ref = dispatch_table.evidenceRef(),
        .profile_ref = profile.evidenceRef(),
        .replay_key_recipe_ref = wrong_source_replay.evidenceRef(),
        .evidence_map_ref = wrong_source_evidence_map.evidenceRef(),
        .trace_map_ref = trace_map_ref,
        .dependencies = wrong_source_dependencies[0..],
    });
    try std.testing.expectEqual(
        error.BoundaryTargetCertificateMismatch,
        wrong_source_certificate.check(policy, elaboration_certificate, wrong_source_surface, source_map, effect_row, trace_map, normal_form, world_ports[0..], port_table, value_table, dispatch_table, profile, wrong_source_replay, wrong_source_evidence_map, normalization_certificate, normalization_trace, normalization_redexes[0..], normalization_rules[0..], static_plans[0..]),
    );

    var wrong_effect_surface_scope = surface;
    wrong_effect_surface_scope.effect_row_ref = Evidence.refFor(Evidence.domains.boundary_elaboration_source_map, 0xC781_00A1, .{ .label = "wrong-effect-row-domain" });
    wrong_effect_surface_scope.surface_fingerprint = wrong_effect_surface_scope.computeFingerprint();
    const wrong_effect_replay = Elaboration.ReplayKeyRecipe.init("target.wrong-effect-replay", wrong_effect_surface_scope.replayScopeRef(), replay.components);
    var wrong_effect_surface = wrong_effect_surface_scope;
    wrong_effect_surface.replay_key_recipe_ref = wrong_effect_replay.evidenceRef();
    wrong_effect_surface.surface_fingerprint = wrong_effect_surface.computeFingerprint();
    const wrong_effect_dependencies = [_]Evidence.Dependency{
        .{ .role = .elaboration_certificate, .ref = elaboration_certificate_ref },
        .{ .role = .elaboration_source_map, .ref = surface.source_map_ref },
        .{ .role = .elaboration_effect_row, .ref = surface.effect_row_ref },
        .{ .role = .elaboration_trace_map, .ref = trace_map_ref },
        .{ .role = .world_surface, .ref = wrong_effect_surface.evidenceRef() },
        .{ .role = .world_port_table, .ref = port_table.evidenceRef() },
        .{ .role = .world_value_table, .ref = value_table.evidenceRef() },
        .{ .role = .world_dispatch_table, .ref = dispatch_table.evidenceRef() },
        .{ .role = .surface_profile, .ref = profile.evidenceRef() },
        .{ .role = .replay_key_recipe, .ref = wrong_effect_replay.evidenceRef() },
        .{ .role = .residual_program, .ref = residual_program_ref },
    };
    const wrong_effect_evidence_map = Elaboration.TargetEvidenceMap.init("target.wrong-effect-evidence", wrong_effect_dependencies[0..]);
    const wrong_effect_certificate = Elaboration.Target.Certificate.init(.{
        .target_label = "target.wrong-effect",
        .policy = policy,
        .elaboration_certificate_ref = elaboration_certificate_ref,
        .residual_program_ref = residual_program_ref,
        .world_surface_ref = wrong_effect_surface.evidenceRef(),
        .port_table_ref = port_table.evidenceRef(),
        .value_table_ref = value_table.evidenceRef(),
        .dispatch_table_ref = dispatch_table.evidenceRef(),
        .profile_ref = profile.evidenceRef(),
        .replay_key_recipe_ref = wrong_effect_replay.evidenceRef(),
        .evidence_map_ref = wrong_effect_evidence_map.evidenceRef(),
        .trace_map_ref = trace_map_ref,
        .dependencies = wrong_effect_dependencies[0..],
    });
    try std.testing.expectEqual(
        error.BoundaryTargetCertificateMismatch,
        wrong_effect_certificate.check(policy, elaboration_certificate, wrong_effect_surface, source_map, effect_row, trace_map, normal_form, world_ports[0..], port_table, value_table, dispatch_table, profile, wrong_effect_replay, wrong_effect_evidence_map, normalization_certificate, normalization_trace, normalization_redexes[0..], normalization_rules[0..], static_plans[0..]),
    );

    const relaxed_profile = Elaboration.SurfaceProfile.init(.{
        .label = "target.relaxed-profile",
        .world_port_count = port_table.entries.len,
        .value_descriptor_count = value_table.entries.len,
        .dispatch_entry_count = dispatch_table.entries.len,
        .no_search_hot_path = false,
        .bounded = true,
    });
    const audit_policy = Elaboration.Target.Policy.auditOnly();
    const audit_elaboration_certificate = Elaboration.Certificate.init(.{
        .elaborated_program_label = "target.audit-elaboration",
        .source_program_ref = residual_program_ref,
        .residual_program_ref = residual_program_ref,
        .closure_certificate_ref = closure_certificate_ref,
        .closure_graph_ref = closure_graph_ref,
        .closure_report_ref = closure_report_ref,
        .source_map_ref = source_map.evidenceRef(),
        .effect_row_ref = effect_row.evidenceRef(),
        .trace_map_ref = trace_map_ref,
        .normal_form_ref = normal_form.evidenceRef(),
        .policy = audit_policy.toElaborationPolicy(),
        .normal_form = .world_ports_only,
        .selected_static_treaty_plan_refs = &.{static_plan.evidenceRef()},
        .world_port_refs = &.{world_port_ref},
        .residual_world_port_refs = &.{world_port_ref},
        .summary_counts = .{
            .root_effect_shapes = 1,
            .world_ports_emitted = 1,
        },
    });
    const audit_elaboration_certificate_ref = audit_elaboration_certificate.evidenceRef();
    const relaxed_surface_scope = Elaboration.WorldSurface.init(.{
        .label = "target.relaxed-surface",
        .residual_program_label = "residual",
        .residual_program_ref = residual_program_ref,
        .elaboration_certificate_ref = audit_elaboration_certificate_ref,
        .source_map_ref = surface.source_map_ref,
        .effect_row_ref = surface.effect_row_ref,
        .port_table_ref = port_table.evidenceRef(),
        .value_table_ref = value_table.evidenceRef(),
        .dispatch_table_ref = dispatch_table.evidenceRef(),
        .profile_ref = relaxed_profile.evidenceRef(),
        .replay_key_recipe_ref = replay.evidenceRef(),
        .normal_form = .world_ports_only,
        .world_port_count = 1,
    });
    const relaxed_replay = Elaboration.ReplayKeyRecipe.init("target.relaxed-replay", relaxed_surface_scope.replayScopeRef(), replay.components);
    const relaxed_surface = Elaboration.WorldSurface.init(.{
        .label = relaxed_surface_scope.label,
        .residual_program_label = relaxed_surface_scope.residual_program_label,
        .residual_program_ref = relaxed_surface_scope.residual_program_ref,
        .elaboration_certificate_ref = relaxed_surface_scope.elaboration_certificate_ref,
        .source_map_ref = relaxed_surface_scope.source_map_ref,
        .effect_row_ref = relaxed_surface_scope.effect_row_ref,
        .port_table_ref = relaxed_surface_scope.port_table_ref,
        .value_table_ref = relaxed_surface_scope.value_table_ref,
        .dispatch_table_ref = relaxed_surface_scope.dispatch_table_ref,
        .profile_ref = relaxed_surface_scope.profile_ref,
        .replay_key_recipe_ref = relaxed_replay.evidenceRef(),
        .normal_form = relaxed_surface_scope.normal_form,
        .world_port_count = relaxed_surface_scope.world_port_count,
    });
    const relaxed_dependencies = [_]Evidence.Dependency{
        .{ .role = .elaboration_certificate, .ref = audit_elaboration_certificate_ref },
        .{ .role = .elaboration_source_map, .ref = surface.source_map_ref },
        .{ .role = .elaboration_effect_row, .ref = surface.effect_row_ref },
        .{ .role = .elaboration_trace_map, .ref = trace_map_ref },
        .{ .role = .world_surface, .ref = relaxed_surface.evidenceRef() },
        .{ .role = .world_port_table, .ref = port_table.evidenceRef() },
        .{ .role = .world_value_table, .ref = value_table.evidenceRef() },
        .{ .role = .world_dispatch_table, .ref = dispatch_table.evidenceRef() },
        .{ .role = .surface_profile, .ref = relaxed_profile.evidenceRef() },
        .{ .role = .replay_key_recipe, .ref = relaxed_replay.evidenceRef() },
        .{ .role = .residual_program, .ref = residual_program_ref },
    };
    const relaxed_evidence_map = Elaboration.TargetEvidenceMap.init("target.relaxed-evidence", relaxed_dependencies[0..]);
    const relaxed_normalization_trace_dependencies = [_]Evidence.Dependency{
        .{ .role = .closure_certificate, .ref = closure_certificate_ref },
        .{ .role = .residual_program, .ref = residual_program_ref },
        .{ .role = .elaboration_source_map, .ref = source_map.evidenceRef() },
        .{ .role = .elaboration_effect_row, .ref = effect_row.evidenceRef() },
        .{ .role = .normal_form, .ref = normal_form.evidenceRef() },
    };
    const relaxed_normalization_trace = Elaboration.Target.Normalization.Trace.init(.{
        .label = "target.relaxed-normalization.trace",
        .root_program_ref = residual_program_ref,
        .closure_certificate_ref = closure_certificate_ref,
        .rewrite_steps = normalization_steps[0..],
        .residual_world_port_refs = normalization_world_ports[0..],
        .final_program_plan_hash = residual_program_ref.fingerprint,
        .final_normal_form = .world_ports_only,
        .evidence_dependencies = relaxed_normalization_trace_dependencies[0..],
    });
    const relaxed_normalization_certificate = Elaboration.Target.Normalization.Certificate.init(.{
        .label = "target.relaxed-normalization.certificate",
        .closure_certificate_ref = closure_certificate_ref,
        .target_policy_fingerprint = audit_policy.fingerprint(),
        .normalization_trace_ref = relaxed_normalization_trace.evidenceRef(),
        .final_program_plan_hash = residual_program_ref.fingerprint,
        .source_map_ref = source_map.evidenceRef(),
        .trace_map_ref = trace_map.evidenceRef(),
        .evidence_map_ref = relaxed_evidence_map.evidenceRef(),
        .effect_row_ref = effect_row.evidenceRef(),
        .normal_form_ref = normal_form.evidenceRef(),
        .world_surface_ref = relaxed_surface.evidenceRef(),
        .dependencies = (&[_]Evidence.Dependency{
            .{ .role = .normalization_trace, .ref = relaxed_normalization_trace.evidenceRef() },
            .{ .role = .elaboration_source_map, .ref = source_map.evidenceRef() },
            .{ .role = .elaboration_trace_map, .ref = trace_map.evidenceRef() },
            .{ .role = .target_evidence_map, .ref = relaxed_evidence_map.evidenceRef() },
            .{ .role = .elaboration_effect_row, .ref = effect_row.evidenceRef() },
            .{ .role = .normal_form, .ref = normal_form.evidenceRef() },
            .{ .role = .world_surface, .ref = relaxed_surface.evidenceRef() },
        })[0..],
    });
    const relaxed_certificate_dependencies = relaxed_dependencies ++ [_]Evidence.Dependency{
        .{ .role = .normalization_certificate, .ref = relaxed_normalization_certificate.evidenceRef() },
    };
    const relaxed_certificate = Elaboration.Target.Certificate.init(.{
        .target_label = "target.relaxed",
        .policy = audit_policy,
        .elaboration_certificate_ref = audit_elaboration_certificate_ref,
        .residual_program_ref = residual_program_ref,
        .world_surface_ref = relaxed_surface.evidenceRef(),
        .port_table_ref = port_table.evidenceRef(),
        .value_table_ref = value_table.evidenceRef(),
        .dispatch_table_ref = dispatch_table.evidenceRef(),
        .profile_ref = relaxed_profile.evidenceRef(),
        .replay_key_recipe_ref = relaxed_replay.evidenceRef(),
        .evidence_map_ref = relaxed_evidence_map.evidenceRef(),
        .trace_map_ref = trace_map_ref,
        .normalization_certificate_ref = relaxed_normalization_certificate.evidenceRef(),
        .dependencies = relaxed_certificate_dependencies[0..],
    });
    try relaxed_certificate.check(audit_policy, audit_elaboration_certificate, relaxed_surface, source_map, effect_row, trace_map, normal_form, world_ports[0..], port_table, value_table, dispatch_table, relaxed_profile, relaxed_replay, relaxed_evidence_map, relaxed_normalization_certificate, relaxed_normalization_trace, normalization_redexes[0..], normalization_rules[0..], static_plans[0..]);

    const strict_policy = Elaboration.Target.Policy.strictClosed();
    const strict_certificate = Elaboration.Target.Certificate.init(.{
        .target_label = "target.strict",
        .policy = strict_policy,
        .elaboration_certificate_ref = elaboration_certificate_ref,
        .residual_program_ref = residual_program_ref,
        .world_surface_ref = surface.evidenceRef(),
        .port_table_ref = port_table.evidenceRef(),
        .value_table_ref = value_table.evidenceRef(),
        .dispatch_table_ref = dispatch_table.evidenceRef(),
        .profile_ref = profile.evidenceRef(),
        .replay_key_recipe_ref = replay.evidenceRef(),
        .evidence_map_ref = evidence_map.evidenceRef(),
        .trace_map_ref = trace_map_ref,
        .dependencies = dependencies[0..],
    });
    try std.testing.expectEqual(
        error.BoundaryTargetPolicyMismatch,
        strict_certificate.check(strict_policy, elaboration_certificate, surface, source_map, effect_row, trace_map, normal_form, world_ports[0..], port_table, value_table, dispatch_table, profile, replay, evidence_map, normalization_certificate, normalization_trace, normalization_redexes[0..], normalization_rules[0..], static_plans[0..]),
    );

    const inconsistent_surface_scope = Elaboration.WorldSurface.init(.{
        .label = "target.inconsistent-surface",
        .residual_program_label = "residual",
        .residual_program_ref = residual_program_ref,
        .elaboration_certificate_ref = elaboration_certificate_ref,
        .source_map_ref = surface.source_map_ref,
        .effect_row_ref = surface.effect_row_ref,
        .port_table_ref = port_table.evidenceRef(),
        .value_table_ref = value_table.evidenceRef(),
        .dispatch_table_ref = dispatch_table.evidenceRef(),
        .profile_ref = profile.evidenceRef(),
        .replay_key_recipe_ref = replay.evidenceRef(),
        .normal_form = .strict_closed,
        .world_port_count = 0,
    });
    const inconsistent_replay = Elaboration.ReplayKeyRecipe.init("target.inconsistent-replay", inconsistent_surface_scope.replayScopeRef(), replay.components);
    const inconsistent_surface = Elaboration.WorldSurface.init(.{
        .label = inconsistent_surface_scope.label,
        .residual_program_label = inconsistent_surface_scope.residual_program_label,
        .residual_program_ref = inconsistent_surface_scope.residual_program_ref,
        .elaboration_certificate_ref = inconsistent_surface_scope.elaboration_certificate_ref,
        .source_map_ref = inconsistent_surface_scope.source_map_ref,
        .effect_row_ref = inconsistent_surface_scope.effect_row_ref,
        .port_table_ref = inconsistent_surface_scope.port_table_ref,
        .value_table_ref = inconsistent_surface_scope.value_table_ref,
        .dispatch_table_ref = inconsistent_surface_scope.dispatch_table_ref,
        .profile_ref = inconsistent_surface_scope.profile_ref,
        .replay_key_recipe_ref = inconsistent_replay.evidenceRef(),
        .normal_form = inconsistent_surface_scope.normal_form,
        .world_port_count = inconsistent_surface_scope.world_port_count,
    });
    const inconsistent_dependencies = [_]Evidence.Dependency{
        .{ .role = .elaboration_certificate, .ref = elaboration_certificate_ref },
        .{ .role = .elaboration_source_map, .ref = surface.source_map_ref },
        .{ .role = .elaboration_effect_row, .ref = surface.effect_row_ref },
        .{ .role = .elaboration_trace_map, .ref = trace_map_ref },
        .{ .role = .world_surface, .ref = inconsistent_surface.evidenceRef() },
        .{ .role = .world_port_table, .ref = port_table.evidenceRef() },
        .{ .role = .world_value_table, .ref = value_table.evidenceRef() },
        .{ .role = .world_dispatch_table, .ref = dispatch_table.evidenceRef() },
        .{ .role = .surface_profile, .ref = profile.evidenceRef() },
        .{ .role = .replay_key_recipe, .ref = inconsistent_replay.evidenceRef() },
        .{ .role = .residual_program, .ref = residual_program_ref },
    };
    const inconsistent_evidence_map = Elaboration.TargetEvidenceMap.init("target.inconsistent-evidence", inconsistent_dependencies[0..]);
    const inconsistent_certificate = Elaboration.Target.Certificate.init(.{
        .target_label = "target.inconsistent",
        .policy = policy,
        .elaboration_certificate_ref = elaboration_certificate_ref,
        .residual_program_ref = residual_program_ref,
        .world_surface_ref = inconsistent_surface.evidenceRef(),
        .port_table_ref = port_table.evidenceRef(),
        .value_table_ref = value_table.evidenceRef(),
        .dispatch_table_ref = dispatch_table.evidenceRef(),
        .profile_ref = profile.evidenceRef(),
        .replay_key_recipe_ref = inconsistent_replay.evidenceRef(),
        .evidence_map_ref = inconsistent_evidence_map.evidenceRef(),
        .trace_map_ref = trace_map_ref,
        .dependencies = inconsistent_dependencies[0..],
    });
    try std.testing.expectEqual(
        error.BoundaryTargetCertificateMismatch,
        inconsistent_certificate.check(policy, elaboration_certificate, inconsistent_surface, source_map, effect_row, trace_map, normal_form, world_ports[0..], port_table, value_table, dispatch_table, profile, inconsistent_replay, inconsistent_evidence_map, normalization_certificate, normalization_trace, normalization_redexes[0..], normalization_rules[0..], static_plans[0..]),
    );
    try std.testing.expectEqual(
        error.BoundaryTargetConformanceMismatch,
        Elaboration.Target.Conformance.check(inconsistent_surface, port_table, value_table, dispatch_table, profile, inconsistent_replay),
    );

    const orphan_value_entries = [_]Elaboration.WorldValueTable.Entry{
        .{ .value_id = 0, .world_port_id = 0, .kind = .payload, .ref = value_ref },
        .{ .value_id = 1, .world_port_id = 0, .kind = .@"resume", .ref = value_ref },
        .{ .value_id = 2, .world_port_id = 0, .kind = .result, .ref = value_ref },
        .{ .value_id = 3, .world_port_id = 7, .kind = .payload, .ref = value_ref },
    };
    const orphan_value_table = Elaboration.WorldValueTable.init("target.orphan-values", orphan_value_entries[0..]);
    const orphan_profile = Elaboration.SurfaceProfile.init(.{
        .label = "target.orphan-profile",
        .world_port_count = port_table.entries.len,
        .value_descriptor_count = orphan_value_table.entries.len,
        .dispatch_entry_count = dispatch_table.entries.len,
        .no_search_hot_path = true,
        .bounded = true,
    });
    const orphan_surface_scope = Elaboration.WorldSurface.init(.{
        .label = "target.orphan-surface",
        .residual_program_label = "residual",
        .residual_program_ref = residual_program_ref,
        .elaboration_certificate_ref = elaboration_certificate_ref,
        .source_map_ref = surface.source_map_ref,
        .effect_row_ref = surface.effect_row_ref,
        .port_table_ref = port_table.evidenceRef(),
        .value_table_ref = orphan_value_table.evidenceRef(),
        .dispatch_table_ref = dispatch_table.evidenceRef(),
        .profile_ref = orphan_profile.evidenceRef(),
        .replay_key_recipe_ref = replay.evidenceRef(),
        .normal_form = .world_ports_only,
        .world_port_count = 1,
    });
    const orphan_replay = Elaboration.ReplayKeyRecipe.init("target.orphan-replay", orphan_surface_scope.replayScopeRef(), replay.components);
    const orphan_surface = Elaboration.WorldSurface.init(.{
        .label = orphan_surface_scope.label,
        .residual_program_label = orphan_surface_scope.residual_program_label,
        .residual_program_ref = orphan_surface_scope.residual_program_ref,
        .elaboration_certificate_ref = orphan_surface_scope.elaboration_certificate_ref,
        .source_map_ref = orphan_surface_scope.source_map_ref,
        .effect_row_ref = orphan_surface_scope.effect_row_ref,
        .port_table_ref = orphan_surface_scope.port_table_ref,
        .value_table_ref = orphan_surface_scope.value_table_ref,
        .dispatch_table_ref = orphan_surface_scope.dispatch_table_ref,
        .profile_ref = orphan_surface_scope.profile_ref,
        .replay_key_recipe_ref = orphan_replay.evidenceRef(),
        .normal_form = orphan_surface_scope.normal_form,
        .world_port_count = orphan_surface_scope.world_port_count,
    });
    const orphan_dependencies = [_]Evidence.Dependency{
        .{ .role = .elaboration_certificate, .ref = elaboration_certificate_ref },
        .{ .role = .elaboration_source_map, .ref = surface.source_map_ref },
        .{ .role = .elaboration_effect_row, .ref = surface.effect_row_ref },
        .{ .role = .elaboration_trace_map, .ref = trace_map_ref },
        .{ .role = .world_surface, .ref = orphan_surface.evidenceRef() },
        .{ .role = .world_port_table, .ref = port_table.evidenceRef() },
        .{ .role = .world_value_table, .ref = orphan_value_table.evidenceRef() },
        .{ .role = .world_dispatch_table, .ref = dispatch_table.evidenceRef() },
        .{ .role = .surface_profile, .ref = orphan_profile.evidenceRef() },
        .{ .role = .replay_key_recipe, .ref = orphan_replay.evidenceRef() },
        .{ .role = .residual_program, .ref = residual_program_ref },
    };
    const orphan_evidence_map = Elaboration.TargetEvidenceMap.init("target.orphan-evidence", orphan_dependencies[0..]);
    const orphan_certificate = Elaboration.Target.Certificate.init(.{
        .target_label = "target.orphan",
        .policy = policy,
        .elaboration_certificate_ref = elaboration_certificate_ref,
        .residual_program_ref = residual_program_ref,
        .world_surface_ref = orphan_surface.evidenceRef(),
        .port_table_ref = port_table.evidenceRef(),
        .value_table_ref = orphan_value_table.evidenceRef(),
        .dispatch_table_ref = dispatch_table.evidenceRef(),
        .profile_ref = orphan_profile.evidenceRef(),
        .replay_key_recipe_ref = orphan_replay.evidenceRef(),
        .evidence_map_ref = orphan_evidence_map.evidenceRef(),
        .trace_map_ref = trace_map_ref,
        .dependencies = orphan_dependencies[0..],
    });
    try std.testing.expectEqual(
        error.BoundaryTargetCertificateMismatch,
        orphan_certificate.check(policy, elaboration_certificate, orphan_surface, source_map, effect_row, trace_map, normal_form, world_ports[0..], port_table, orphan_value_table, dispatch_table, orphan_profile, orphan_replay, orphan_evidence_map, normalization_certificate, normalization_trace, normalization_redexes[0..], normalization_rules[0..], static_plans[0..]),
    );

    const other_value_ref = Evidence.BoundaryValueRef.init("i64", null);
    const mismatched_value_entries = [_]Elaboration.WorldValueTable.Entry{
        .{ .value_id = 0, .world_port_id = 0, .kind = .payload, .ref = other_value_ref },
        .{ .value_id = 1, .world_port_id = 0, .kind = .@"resume", .ref = value_ref },
        .{ .value_id = 2, .world_port_id = 0, .kind = .result, .ref = value_ref },
    };
    const mismatched_value_table = Elaboration.WorldValueTable.init("target.mismatched-values", mismatched_value_entries[0..]);
    const mismatched_surface_scope = Elaboration.WorldSurface.init(.{
        .label = "target.mismatched-surface",
        .residual_program_label = "residual",
        .residual_program_ref = residual_program_ref,
        .elaboration_certificate_ref = elaboration_certificate_ref,
        .source_map_ref = surface.source_map_ref,
        .effect_row_ref = surface.effect_row_ref,
        .port_table_ref = port_table.evidenceRef(),
        .value_table_ref = mismatched_value_table.evidenceRef(),
        .dispatch_table_ref = dispatch_table.evidenceRef(),
        .profile_ref = profile.evidenceRef(),
        .replay_key_recipe_ref = replay.evidenceRef(),
        .normal_form = .world_ports_only,
        .world_port_count = 1,
    });
    const mismatched_replay = Elaboration.ReplayKeyRecipe.init("target.mismatched-replay", mismatched_surface_scope.replayScopeRef(), replay.components);
    const mismatched_surface = Elaboration.WorldSurface.init(.{
        .label = mismatched_surface_scope.label,
        .residual_program_label = mismatched_surface_scope.residual_program_label,
        .residual_program_ref = mismatched_surface_scope.residual_program_ref,
        .elaboration_certificate_ref = mismatched_surface_scope.elaboration_certificate_ref,
        .source_map_ref = mismatched_surface_scope.source_map_ref,
        .effect_row_ref = mismatched_surface_scope.effect_row_ref,
        .port_table_ref = mismatched_surface_scope.port_table_ref,
        .value_table_ref = mismatched_surface_scope.value_table_ref,
        .dispatch_table_ref = mismatched_surface_scope.dispatch_table_ref,
        .profile_ref = mismatched_surface_scope.profile_ref,
        .replay_key_recipe_ref = mismatched_replay.evidenceRef(),
        .normal_form = mismatched_surface_scope.normal_form,
        .world_port_count = mismatched_surface_scope.world_port_count,
    });
    const mismatched_dependencies = [_]Evidence.Dependency{
        .{ .role = .elaboration_certificate, .ref = elaboration_certificate_ref },
        .{ .role = .elaboration_source_map, .ref = surface.source_map_ref },
        .{ .role = .elaboration_effect_row, .ref = surface.effect_row_ref },
        .{ .role = .elaboration_trace_map, .ref = trace_map_ref },
        .{ .role = .world_surface, .ref = mismatched_surface.evidenceRef() },
        .{ .role = .world_port_table, .ref = port_table.evidenceRef() },
        .{ .role = .world_value_table, .ref = mismatched_value_table.evidenceRef() },
        .{ .role = .world_dispatch_table, .ref = dispatch_table.evidenceRef() },
        .{ .role = .surface_profile, .ref = profile.evidenceRef() },
        .{ .role = .replay_key_recipe, .ref = mismatched_replay.evidenceRef() },
        .{ .role = .residual_program, .ref = residual_program_ref },
    };
    const mismatched_evidence_map = Elaboration.TargetEvidenceMap.init("target.mismatched-evidence", mismatched_dependencies[0..]);
    const mismatched_certificate = Elaboration.Target.Certificate.init(.{
        .target_label = "target.mismatched",
        .policy = policy,
        .elaboration_certificate_ref = elaboration_certificate_ref,
        .residual_program_ref = residual_program_ref,
        .world_surface_ref = mismatched_surface.evidenceRef(),
        .port_table_ref = port_table.evidenceRef(),
        .value_table_ref = mismatched_value_table.evidenceRef(),
        .dispatch_table_ref = dispatch_table.evidenceRef(),
        .profile_ref = profile.evidenceRef(),
        .replay_key_recipe_ref = mismatched_replay.evidenceRef(),
        .evidence_map_ref = mismatched_evidence_map.evidenceRef(),
        .trace_map_ref = trace_map_ref,
        .dependencies = mismatched_dependencies[0..],
    });
    try std.testing.expectEqual(
        error.BoundaryTargetCertificateMismatch,
        mismatched_certificate.check(policy, elaboration_certificate, mismatched_surface, source_map, effect_row, trace_map, normal_form, world_ports[0..], port_table, mismatched_value_table, dispatch_table, profile, mismatched_replay, mismatched_evidence_map, normalization_certificate, normalization_trace, normalization_redexes[0..], normalization_rules[0..], static_plans[0..]),
    );

    const empty_evidence_map = Elaboration.TargetEvidenceMap.init("target.empty-evidence", &.{});
    const empty_dependency_certificate = Elaboration.Target.Certificate.init(.{
        .target_label = "target.empty-deps",
        .policy = policy,
        .elaboration_certificate_ref = elaboration_certificate_ref,
        .residual_program_ref = residual_program_ref,
        .world_surface_ref = surface.evidenceRef(),
        .port_table_ref = port_table.evidenceRef(),
        .value_table_ref = value_table.evidenceRef(),
        .dispatch_table_ref = dispatch_table.evidenceRef(),
        .profile_ref = profile.evidenceRef(),
        .replay_key_recipe_ref = replay.evidenceRef(),
        .evidence_map_ref = empty_evidence_map.evidenceRef(),
        .trace_map_ref = trace_map_ref,
        .dependencies = &.{},
    });
    try std.testing.expectEqual(
        error.BoundaryTargetCertificateMismatch,
        empty_dependency_certificate.check(policy, elaboration_certificate, surface, source_map, effect_row, trace_map, normal_form, world_ports[0..], port_table, value_table, dispatch_table, profile, replay, empty_evidence_map, normalization_certificate, normalization_trace, normalization_redexes[0..], normalization_rules[0..], static_plans[0..]),
    );
}

test "elaboration certificate source map world port lowering boundary normal form provider linking runtime agreement" {
    const Closure = Program.BoundaryClosure;
    const Elaboration = Program.BoundaryClosure.Elaboration;
    const source_ref = Evidence.refFor(Evidence.domains.program_plan, 0xE1B001, .{ .label = "source" });
    const residual_ref = Evidence.refFor(Evidence.domains.program_plan, 0xE1B002, .{ .label = "residual" });
    const provider_ref = Evidence.refFor(Evidence.domains.provider_manifest, 0xE1B003, .{ .label = "approval.provider.manifest" });
    const provider_offer_ref = Evidence.refFor(Evidence.domains.provider_offer, 0xE1B004, .{ .label = "approval.provider.offer" });
    const provider_program_ref = Evidence.refFor(Evidence.domains.program_plan, 0xE1B005, .{ .label = "approval.provider" });
    const provider_morphism_ref = Evidence.refFor(Evidence.domains.morphism_offer, 0xE1B00D, .{ .label = "approval.provider.morphism" });
    const provider_pipeline_ref = Evidence.refFor(Evidence.domains.pipeline, 0xE1B00C, .{ .label = "provider-program-pipeline-proof" });
    const source_resume_ref = Evidence.BoundaryValueRef.init("i32", null);
    const provider_static_plan_deps = [_]Evidence.Dependency{.{
        .role = .residual_program,
        .ref = residual_ref,
    }};
    const source_shape = Closure.EffectShape.init(.{
        .program_label = "source",
        .kind = .operation,
        .site_index = 4,
        .protocol_label = "approval",
        .expected_resume_ref = source_resume_ref,
    });
    const source_shape_ref = source_shape.evidenceRef();
    const world_shape = Closure.EffectShape.init(.{
        .program_label = "source",
        .kind = .operation,
        .site_index = 5,
        .protocol_label = "approval",
    });
    const world_shape_ref = world_shape.evidenceRef();
    const static_plan = Closure.StaticTreatyPlan.init(.{
        .label = "approval.plan",
        .source_shape = source_shape,
        .selected_semantic_body = .boundary_program,
        .selected_provider_ref = provider_ref,
        .selected_provider_offer_ref = provider_offer_ref,
        .selected_provider_program_ref = provider_program_ref,
        .selected_provider_program_mapping_fingerprint = 0xE1B00B,
        .selected_provider_program_request_mapping_tag = "payload_to_args",
        .selected_provider_program_result_mapping_tag = "result_to_resume",
        .selected_provider_program_effect_shape_count = 0,
        .selected_provider_program_effect_shape_fingerprint = Evidence.fingerprintBoundaryEffectShapeSet(&.{}),
        .dependencies = provider_static_plan_deps[0..],
    });
    const static_plan_ref = static_plan.evidenceRef();
    const intrinsic_ref = Evidence.refFor(Evidence.domains.host_intrinsic, 0xE1B006, .{
        .label = "approval.world.intrinsic",
        .kind_tag = @tagName(Evidence.HostIntrinsic.Kind.provider_function),
    });
    const world_static_plan = Closure.StaticTreatyPlan.init(.{
        .label = "approval.world.plan",
        .source_shape = world_shape,
        .selected_semantic_body = .host_intrinsic,
        .selected_intrinsic_ref = intrinsic_ref,
        .host_intrinsic = true,
    });
    const world_static_plan_ref = world_static_plan.evidenceRef();
    const static_plans = [_]Closure.StaticTreatyPlan{ static_plan, world_static_plan };
    const world_port = Closure.WorldPort.init(.{
        .label = "approval.world",
        .kind = .test_fixture,
        .effect_shape_ref = world_shape_ref,
        .exposed_intrinsic_ref = intrinsic_ref,
    });
    const world_port_ref = world_port.evidenceRef();
    const closure_certificate_ref = Evidence.refFor(Evidence.domains.boundary_closure_certificate, 0xE1B007, .{
        .format_version = Evidence.domains.boundary_closure_certificate.format_version,
        .label = "closure-certificate",
    });
    const closure_graph_ref = Evidence.refFor(Evidence.domains.boundary_closure_graph, 0xE1B008, .{ .label = "closure-graph" });
    const closure_report_ref = Evidence.refFor(Evidence.domains.boundary_closure_report, 0xE1B009, .{ .label = "closure-report" });
    const source_entries = [_]Elaboration.SourceMap.Entry{
        .{
            .source_ref = source_shape_ref,
            .residual_ref = residual_ref,
            .source_site_index = 4,
            .provider_program_ref = provider_program_ref,
            .static_treaty_plan_ref = static_plan_ref,
            .disposition = .provider_program_linked,
            .label = "provider linking",
        },
        .{
            .source_ref = world_shape_ref,
            .residual_ref = residual_ref,
            .source_site_index = 5,
            .residual_site_index = 5,
            .static_treaty_plan_ref = world_static_plan_ref,
            .world_port_ref = world_port_ref,
            .disposition = .world_port_lowered,
            .label = "world port lowering",
        },
    };
    const source_map = Elaboration.SourceMap.init("runtime-agreement-source-map", source_entries[0..], &.{});
    try std.testing.expect(source_map.residualForSourceShape(source_shape_ref).?.eql(residual_ref));
    try std.testing.expect(source_map.sourceForResidualSite(5).?.eql(world_shape_ref));
    try std.testing.expect(source_map.worldPortForResidualSite(5).?.eql(world_port_ref));
    try std.testing.expect(source_map.staticPlanForElaboratedRoute(source_shape_ref).?.eql(static_plan_ref));

    const trace_entries = [_]Elaboration.TraceMap.Entry{
        .{ .source_ref = source_shape_ref, .residual_ref = residual_ref, .trace_label = "provider linking" },
        .{ .source_ref = world_shape_ref, .residual_ref = world_port_ref, .trace_label = "world port lowering" },
    };
    const trace_map = Elaboration.TraceMap.init("runtime-agreement-trace-map", trace_entries[0..]);
    const effect_row = Elaboration.EffectRow.init(.{
        .label = "runtime-agreement-effect-row",
        .source_program_ref = source_ref,
        .residual_program_ref = residual_ref,
        .normal_form = .world_ports_only,
        .source_effect_shapes = 2,
        .closed_effect_shapes = 1,
        .provider_program_links = 1,
        .world_ports = 1,
    });
    try std.testing.expectEqual(@as(usize, 1), effect_row.linked_provider_programs);
    try std.testing.expectEqual(@as(usize, 1), effect_row.residual_world_ports);
    try std.testing.expect(effect_row.world_ports_only);

    const normal_form = Elaboration.NormalForm.init("runtime-agreement-normal-form", .world_ports_only, closure_certificate_ref, effect_row.evidenceRef(), 0);
    const allowed_world_ports = [_]u64{world_port_ref.fingerprint};
    var policy = Elaboration.Policy.worldBoundary();
    policy.closure_policy.allowed_world_port_fingerprints = allowed_world_ports[0..];
    const dependencies = [_]Evidence.Dependency{
        .{ .role = .closure_certificate, .ref = closure_certificate_ref },
        .{ .role = .elaboration_source_map, .ref = source_map.evidenceRef() },
        .{ .role = .elaboration_trace_map, .ref = trace_map.evidenceRef() },
        .{ .role = .normal_form, .ref = normal_form.evidenceRef() },
    };
    const elaboration_certificate = Elaboration.Certificate.init(.{
        .elaborated_program_label = "runtime-agreement-residual",
        .source_program_ref = source_ref,
        .residual_program_ref = residual_ref,
        .closure_certificate_ref = closure_certificate_ref,
        .closure_graph_ref = closure_graph_ref,
        .closure_report_ref = closure_report_ref,
        .source_map_ref = source_map.evidenceRef(),
        .effect_row_ref = effect_row.evidenceRef(),
        .trace_map_ref = trace_map.evidenceRef(),
        .normal_form_ref = normal_form.evidenceRef(),
        .policy = policy,
        .normal_form = .world_ports_only,
        .selected_static_treaty_plan_refs = &.{ static_plan_ref, world_static_plan_ref },
        .world_port_refs = &.{world_port_ref},
        .residual_world_port_refs = &.{world_port_ref},
        .inlined_provider_program_refs = &.{provider_program_ref},
        .summary_counts = .{
            .root_effect_shapes = 2,
            .internal_routes_elaborated = 1,
            .provider_programs_linked = 1,
            .world_ports_emitted = 1,
        },
        .dependencies = dependencies[0..],
    });
    const world_ports = [_]Closure.WorldPort{world_port};
    try elaboration_certificate.check(policy, closure_graph_ref, closure_report_ref, closure_certificate_ref, source_map, effect_row, trace_map, normal_form, static_plans[0..], world_ports[0..]);
    const morphed_provider_static_plan_deps = [_]Evidence.Dependency{
        .{ .role = .residual_program, .ref = residual_ref },
        .{ .role = .morphism, .ref = provider_morphism_ref },
        .{ .role = .pipeline, .ref = provider_pipeline_ref },
    };
    const morphed_provider_static_plan = Closure.StaticTreatyPlan.init(.{
        .label = "approval.plan.morphed",
        .source_shape = source_shape,
        .selected_semantic_body = .boundary_program,
        .selected_provider_ref = provider_ref,
        .selected_provider_offer_ref = provider_offer_ref,
        .selected_provider_program_ref = provider_program_ref,
        .selected_provider_program_mapping_fingerprint = 0xE1B00B,
        .selected_provider_program_request_mapping_tag = "payload_to_args",
        .selected_provider_program_result_mapping_tag = "result_to_resume",
        .selected_provider_program_effect_shape_count = 0,
        .selected_provider_program_effect_shape_fingerprint = Evidence.fingerprintBoundaryEffectShapeSet(&.{}),
        .selected_morphism_ref = provider_morphism_ref,
        .selected_morphism_target_shape_ref = source_shape.evidenceRef(),
        .selected_morphism_target_shape = source_shape,
        .selected_morphism_semantic_body = .pipeline,
        .dependencies = morphed_provider_static_plan_deps[0..],
    });
    const morphed_provider_static_plan_ref = morphed_provider_static_plan.evidenceRef();
    var morphed_provider_entries = source_entries;
    morphed_provider_entries[0].static_treaty_plan_ref = morphed_provider_static_plan_ref;
    const morphed_provider_map = Elaboration.SourceMap.init("runtime-agreement-morphed-provider-map", morphed_provider_entries[0..], &.{});
    const morphed_provider_static_plans = [_]Closure.StaticTreatyPlan{ morphed_provider_static_plan, world_static_plan };
    const morphed_provider_dependencies = [_]Evidence.Dependency{
        .{ .role = .closure_certificate, .ref = closure_certificate_ref },
        .{ .role = .elaboration_source_map, .ref = morphed_provider_map.evidenceRef() },
        .{ .role = .elaboration_trace_map, .ref = trace_map.evidenceRef() },
        .{ .role = .normal_form, .ref = normal_form.evidenceRef() },
    };
    const morphed_provider_certificate = Elaboration.Certificate.init(.{
        .elaborated_program_label = "runtime-agreement-residual",
        .source_program_ref = source_ref,
        .residual_program_ref = residual_ref,
        .closure_certificate_ref = closure_certificate_ref,
        .closure_graph_ref = closure_graph_ref,
        .closure_report_ref = closure_report_ref,
        .source_map_ref = morphed_provider_map.evidenceRef(),
        .effect_row_ref = effect_row.evidenceRef(),
        .trace_map_ref = trace_map.evidenceRef(),
        .normal_form_ref = normal_form.evidenceRef(),
        .policy = policy,
        .normal_form = .world_ports_only,
        .selected_static_treaty_plan_refs = &.{ morphed_provider_static_plan_ref, world_static_plan_ref },
        .world_port_refs = &.{world_port_ref},
        .residual_world_port_refs = &.{world_port_ref},
        .inlined_provider_program_refs = &.{provider_program_ref},
        .summary_counts = .{
            .root_effect_shapes = 2,
            .internal_routes_elaborated = 1,
            .provider_programs_linked = 1,
            .world_ports_emitted = 1,
        },
        .dependencies = morphed_provider_dependencies[0..],
    });
    try morphed_provider_certificate.check(policy, closure_graph_ref, closure_report_ref, closure_certificate_ref, morphed_provider_map, effect_row, trace_map, normal_form, morphed_provider_static_plans[0..], world_ports[0..]);
    const missing_morphism_provider_static_plan = Closure.StaticTreatyPlan.init(.{
        .label = "approval.plan.morphed.missing-proof",
        .source_shape = source_shape,
        .selected_semantic_body = .boundary_program,
        .selected_provider_ref = provider_ref,
        .selected_provider_offer_ref = provider_offer_ref,
        .selected_provider_program_ref = provider_program_ref,
        .selected_provider_program_mapping_fingerprint = 0xE1B00B,
        .selected_provider_program_request_mapping_tag = "payload_to_args",
        .selected_provider_program_result_mapping_tag = "result_to_resume",
        .selected_provider_program_effect_shape_count = 0,
        .selected_provider_program_effect_shape_fingerprint = Evidence.fingerprintBoundaryEffectShapeSet(&.{}),
        .selected_morphism_ref = provider_morphism_ref,
        .selected_morphism_semantic_body = .pipeline,
        .dependencies = provider_static_plan_deps[0..],
    });
    const missing_morphism_provider_static_plan_ref = missing_morphism_provider_static_plan.evidenceRef();
    var missing_morphism_provider_entries = source_entries;
    missing_morphism_provider_entries[0].static_treaty_plan_ref = missing_morphism_provider_static_plan_ref;
    const missing_morphism_provider_map = Elaboration.SourceMap.init("runtime-agreement-missing-morphism-provider-map", missing_morphism_provider_entries[0..], &.{});
    const missing_morphism_provider_static_plans = [_]Closure.StaticTreatyPlan{ missing_morphism_provider_static_plan, world_static_plan };
    const missing_morphism_provider_dependencies = [_]Evidence.Dependency{
        .{ .role = .closure_certificate, .ref = closure_certificate_ref },
        .{ .role = .elaboration_source_map, .ref = missing_morphism_provider_map.evidenceRef() },
        .{ .role = .elaboration_trace_map, .ref = trace_map.evidenceRef() },
        .{ .role = .normal_form, .ref = normal_form.evidenceRef() },
    };
    const missing_morphism_provider_certificate = Elaboration.Certificate.init(.{
        .elaborated_program_label = "runtime-agreement-residual",
        .source_program_ref = source_ref,
        .residual_program_ref = residual_ref,
        .closure_certificate_ref = closure_certificate_ref,
        .closure_graph_ref = closure_graph_ref,
        .closure_report_ref = closure_report_ref,
        .source_map_ref = missing_morphism_provider_map.evidenceRef(),
        .effect_row_ref = effect_row.evidenceRef(),
        .trace_map_ref = trace_map.evidenceRef(),
        .normal_form_ref = normal_form.evidenceRef(),
        .policy = policy,
        .normal_form = .world_ports_only,
        .selected_static_treaty_plan_refs = &.{ missing_morphism_provider_static_plan_ref, world_static_plan_ref },
        .world_port_refs = &.{world_port_ref},
        .residual_world_port_refs = &.{world_port_ref},
        .inlined_provider_program_refs = &.{provider_program_ref},
        .summary_counts = .{
            .root_effect_shapes = 2,
            .internal_routes_elaborated = 1,
            .provider_programs_linked = 1,
            .world_ports_emitted = 1,
        },
        .dependencies = missing_morphism_provider_dependencies[0..],
    });
    try std.testing.expectEqual(
        error.BoundaryElaborationCertificateMismatch,
        missing_morphism_provider_certificate.check(policy, closure_graph_ref, closure_report_ref, closure_certificate_ref, missing_morphism_provider_map, effect_row, trace_map, normal_form, missing_morphism_provider_static_plans[0..], world_ports[0..]),
    );
    const provider_program_label_copy = try std.testing.allocator.dupe(u8, "approval.provider");
    defer std.testing.allocator.free(provider_program_label_copy);
    const provider_program_ref_copy = Evidence.refFor(Evidence.domains.program_plan, provider_program_ref.fingerprint, .{ .label = provider_program_label_copy });
    var copied_provider_entries = source_entries;
    copied_provider_entries[0].provider_program_ref = provider_program_ref_copy;
    const copied_provider_map = Elaboration.SourceMap.init("runtime-agreement-copied-provider-map", copied_provider_entries[0..], &.{});
    const copied_provider_dependencies = [_]Evidence.Dependency{
        .{ .role = .closure_certificate, .ref = closure_certificate_ref },
        .{ .role = .elaboration_source_map, .ref = copied_provider_map.evidenceRef() },
        .{ .role = .elaboration_trace_map, .ref = trace_map.evidenceRef() },
        .{ .role = .normal_form, .ref = normal_form.evidenceRef() },
    };
    const copied_provider_certificate = Elaboration.Certificate.init(.{
        .elaborated_program_label = "runtime-agreement-residual",
        .source_program_ref = source_ref,
        .residual_program_ref = residual_ref,
        .closure_certificate_ref = closure_certificate_ref,
        .closure_graph_ref = closure_graph_ref,
        .closure_report_ref = closure_report_ref,
        .source_map_ref = copied_provider_map.evidenceRef(),
        .effect_row_ref = effect_row.evidenceRef(),
        .trace_map_ref = trace_map.evidenceRef(),
        .normal_form_ref = normal_form.evidenceRef(),
        .policy = policy,
        .normal_form = .world_ports_only,
        .selected_static_treaty_plan_refs = &.{ static_plan_ref, world_static_plan_ref },
        .world_port_refs = &.{world_port_ref},
        .residual_world_port_refs = &.{world_port_ref},
        .inlined_provider_program_refs = &.{provider_program_ref_copy},
        .summary_counts = .{
            .root_effect_shapes = 2,
            .internal_routes_elaborated = 1,
            .provider_programs_linked = 1,
            .world_ports_emitted = 1,
        },
        .dependencies = copied_provider_dependencies[0..],
    });
    try copied_provider_certificate.check(policy, closure_graph_ref, closure_report_ref, closure_certificate_ref, copied_provider_map, effect_row, trace_map, normal_form, static_plans[0..], world_ports[0..]);
    const duplicate_plan_entries = [_]Elaboration.SourceMap.Entry{ source_entries[0], source_entries[0] };
    const duplicate_plan_map = Elaboration.SourceMap.init("runtime-agreement-duplicate-plan-map", duplicate_plan_entries[0..], &.{});
    const duplicate_plan_trace_entries = [_]Elaboration.TraceMap.Entry{ trace_entries[0], trace_entries[0] };
    const duplicate_plan_trace_map = Elaboration.TraceMap.init("runtime-agreement-duplicate-plan-trace-map", duplicate_plan_trace_entries[0..]);
    const duplicate_plan_effect_row = Elaboration.EffectRow.init(.{
        .label = "runtime-agreement-duplicate-plan-effect-row",
        .source_program_ref = source_ref,
        .residual_program_ref = residual_ref,
        .normal_form = .strict_closed,
        .source_effect_shapes = 2,
        .closed_effect_shapes = 2,
        .provider_program_links = 2,
    });
    const duplicate_plan_normal_form = Elaboration.NormalForm.init("runtime-agreement-duplicate-plan-normal-form", .strict_closed, closure_certificate_ref, duplicate_plan_effect_row.evidenceRef(), 0);
    const duplicate_plan_dependencies = [_]Evidence.Dependency{
        .{ .role = .closure_certificate, .ref = closure_certificate_ref },
        .{ .role = .elaboration_source_map, .ref = duplicate_plan_map.evidenceRef() },
        .{ .role = .elaboration_trace_map, .ref = duplicate_plan_trace_map.evidenceRef() },
        .{ .role = .normal_form, .ref = duplicate_plan_normal_form.evidenceRef() },
    };
    const duplicate_plan_certificate = Elaboration.Certificate.init(.{
        .elaborated_program_label = "runtime-agreement-residual",
        .source_program_ref = source_ref,
        .residual_program_ref = residual_ref,
        .closure_certificate_ref = closure_certificate_ref,
        .closure_graph_ref = closure_graph_ref,
        .closure_report_ref = closure_report_ref,
        .source_map_ref = duplicate_plan_map.evidenceRef(),
        .effect_row_ref = duplicate_plan_effect_row.evidenceRef(),
        .trace_map_ref = duplicate_plan_trace_map.evidenceRef(),
        .normal_form_ref = duplicate_plan_normal_form.evidenceRef(),
        .policy = policy,
        .normal_form = .strict_closed,
        .selected_static_treaty_plan_refs = &.{ static_plan_ref, static_plan_ref },
        .inlined_provider_program_refs = &.{provider_program_ref},
        .summary_counts = .{
            .root_effect_shapes = 2,
            .internal_routes_elaborated = 2,
            .provider_programs_linked = 1,
        },
        .dependencies = duplicate_plan_dependencies[0..],
    });
    try std.testing.expectEqual(
        error.BoundaryElaborationCertificateMismatch,
        duplicate_plan_certificate.check(policy, closure_graph_ref, closure_report_ref, closure_certificate_ref, duplicate_plan_map, duplicate_plan_effect_row, duplicate_plan_trace_map, duplicate_plan_normal_form, static_plans[0..], &.{}),
    );
    var stale_static_plan = static_plan;
    stale_static_plan.direct_candidate_count += 1;
    const stale_static_plans = [_]Closure.StaticTreatyPlan{ stale_static_plan, world_static_plan };
    try std.testing.expectEqual(
        error.BoundaryElaborationCertificateMismatch,
        elaboration_certificate.check(policy, closure_graph_ref, closure_report_ref, closure_certificate_ref, source_map, effect_row, trace_map, normal_form, stale_static_plans[0..], world_ports[0..]),
    );
    const binding_provider_ref = Evidence.refFor(Evidence.domains.provider_manifest, 0xE1B004, .{
        .format_version = Evidence.domains.provider_manifest.format_version,
        .label = "approval.provider.manifest",
    });
    const binding_provider_offer_ref = Evidence.refFor(Evidence.domains.provider_offer, 0xE1B00C, .{
        .format_version = Evidence.domains.provider_offer.format_version,
        .label = "approval.provider.offer",
    });
    const binding_plan = Closure.StaticTreatyPlan.init(.{
        .label = "approval.binding.plan",
        .source_shape = source_shape,
        .selected_semantic_body = .boundary_program,
        .selected_provider_ref = binding_provider_ref,
        .selected_provider_offer_ref = binding_provider_offer_ref,
        .selected_provider_program_ref = provider_program_ref,
        .selected_provider_program_mapping_fingerprint = 0xE1B00A,
        .selected_provider_program_request_mapping_tag = "payload_to_args",
        .selected_provider_program_result_mapping_tag = "result_to_resume",
        .selected_provider_program_effect_shape_count = 0,
        .selected_provider_program_effect_shape_fingerprint = Evidence.fingerprintBoundaryEffectShapeSet(&.{}),
    });
    const binding_provider_program_alias_ref = Evidence.refFor(Evidence.domains.program_plan, provider_program_ref.fingerprint, .{ .label = "approval.provider.alias" });
    const alias_binding_plan = Closure.StaticTreatyPlan.init(.{
        .label = "approval.binding.plan",
        .source_shape = source_shape,
        .selected_semantic_body = .boundary_program,
        .selected_provider_ref = binding_provider_ref,
        .selected_provider_offer_ref = binding_provider_offer_ref,
        .selected_provider_program_ref = binding_provider_program_alias_ref,
        .selected_provider_program_mapping_fingerprint = 0xE1B00A,
        .selected_provider_program_request_mapping_tag = "payload_to_args",
        .selected_provider_program_result_mapping_tag = "result_to_resume",
        .selected_provider_program_effect_shape_count = 0,
        .selected_provider_program_effect_shape_fingerprint = Evidence.fingerprintBoundaryEffectShapeSet(&.{}),
    });
    const binding_ref = Evidence.refForProviderProgramResidualBinding(binding_plan, residual_ref).?;
    const alias_binding_ref = Evidence.refForProviderProgramResidualBinding(alias_binding_plan, residual_ref).?;
    try std.testing.expect(!binding_ref.eql(alias_binding_ref));
    const morph_target_shape_a = Closure.EffectShape.init(.{
        .program_label = "approval.binding.target",
        .kind = .operation,
        .site_index = 0,
        .protocol_label = "approval",
        .protocol_op_fingerprint = 0xE1B10A,
    });
    const morph_target_shape_b = Closure.EffectShape.init(.{
        .program_label = "approval.binding.target",
        .kind = .operation,
        .site_index = 0,
        .protocol_label = "approval",
        .protocol_op_fingerprint = 0xE1B10B,
    });
    const morphism_ref = Evidence.refFor(Evidence.domains.morphism_offer, 0xE1B10C, .{ .label = "approval.binding.morphism" });
    const morph_bind_plan_a = Closure.StaticTreatyPlan.init(.{
        .label = "approval.binding.morphism.a",
        .source_shape = source_shape,
        .selected_semantic_body = .boundary_program,
        .selected_provider_ref = binding_provider_ref,
        .selected_provider_offer_ref = binding_provider_offer_ref,
        .selected_provider_program_ref = provider_program_ref,
        .selected_provider_program_mapping_fingerprint = 0xE1B00A,
        .selected_provider_program_request_mapping_tag = "payload_to_args",
        .selected_provider_program_result_mapping_tag = "result_to_resume",
        .selected_provider_program_effect_shape_count = 0,
        .selected_provider_program_effect_shape_fingerprint = Evidence.fingerprintBoundaryEffectShapeSet(&.{}),
        .selected_morphism_ref = morphism_ref,
        .selected_morphism_target_shape_ref = morph_target_shape_a.evidenceRef(),
        .selected_morphism_target_shape = morph_target_shape_a,
    });
    const morph_bind_plan_b = Closure.StaticTreatyPlan.init(.{
        .label = "approval.binding.morphism.b",
        .source_shape = source_shape,
        .selected_semantic_body = .boundary_program,
        .selected_provider_ref = binding_provider_ref,
        .selected_provider_offer_ref = binding_provider_offer_ref,
        .selected_provider_program_ref = provider_program_ref,
        .selected_provider_program_mapping_fingerprint = 0xE1B00A,
        .selected_provider_program_request_mapping_tag = "payload_to_args",
        .selected_provider_program_result_mapping_tag = "result_to_resume",
        .selected_provider_program_effect_shape_count = 0,
        .selected_provider_program_effect_shape_fingerprint = Evidence.fingerprintBoundaryEffectShapeSet(&.{}),
        .selected_morphism_ref = morphism_ref,
        .selected_morphism_target_shape_ref = morph_target_shape_b.evidenceRef(),
        .selected_morphism_target_shape = morph_target_shape_b,
    });
    const morph_bind_ref_a = Evidence.refForProviderProgramResidualBinding(morph_bind_plan_a, residual_ref).?;
    const morph_bind_ref_b = Evidence.refForProviderProgramResidualBinding(morph_bind_plan_b, residual_ref).?;
    try std.testing.expect(!morph_bind_ref_a.eql(morph_bind_ref_b));
    try std.testing.expect(!morph_bind_ref_a.eql(binding_ref));
    const provider_program_alias_ref = Evidence.refFor(Evidence.domains.program_plan, provider_program_ref.fingerprint, .{ .label = "approval.provider.alias" });
    var forged_provider_entries = source_entries;
    forged_provider_entries[0].provider_program_ref = provider_program_alias_ref;
    const forged_provider_source_map = Elaboration.SourceMap.init("runtime-agreement-forged-provider-map", forged_provider_entries[0..], &.{});
    const forged_provider_dependencies = [_]Evidence.Dependency{
        .{ .role = .closure_certificate, .ref = closure_certificate_ref },
        .{ .role = .elaboration_source_map, .ref = forged_provider_source_map.evidenceRef() },
        .{ .role = .elaboration_trace_map, .ref = trace_map.evidenceRef() },
        .{ .role = .normal_form, .ref = normal_form.evidenceRef() },
    };
    const forged_provider_certificate = Elaboration.Certificate.init(.{
        .elaborated_program_label = "runtime-agreement-residual",
        .source_program_ref = source_ref,
        .residual_program_ref = residual_ref,
        .closure_certificate_ref = closure_certificate_ref,
        .closure_graph_ref = closure_graph_ref,
        .closure_report_ref = closure_report_ref,
        .source_map_ref = forged_provider_source_map.evidenceRef(),
        .effect_row_ref = effect_row.evidenceRef(),
        .trace_map_ref = trace_map.evidenceRef(),
        .normal_form_ref = normal_form.evidenceRef(),
        .policy = policy,
        .normal_form = .world_ports_only,
        .selected_static_treaty_plan_refs = &.{ static_plan_ref, world_static_plan_ref },
        .world_port_refs = &.{world_port_ref},
        .residual_world_port_refs = &.{world_port_ref},
        .inlined_provider_program_refs = &.{provider_program_alias_ref},
        .summary_counts = .{
            .root_effect_shapes = 2,
            .internal_routes_elaborated = 1,
            .provider_programs_linked = 1,
            .world_ports_emitted = 1,
        },
        .dependencies = forged_provider_dependencies[0..],
    });
    try std.testing.expectEqual(
        error.BoundaryElaborationCertificateMismatch,
        forged_provider_certificate.check(policy, closure_graph_ref, closure_report_ref, closure_certificate_ref, forged_provider_source_map, effect_row, trace_map, normal_form, static_plans[0..], world_ports[0..]),
    );
    var intrinsic_blocking_policy = policy;
    intrinsic_blocking_policy.allow_intrinsic_world_ports = false;
    const intrinsic_blocking_certificate = Elaboration.Certificate.init(.{
        .elaborated_program_label = "runtime-agreement-residual",
        .source_program_ref = source_ref,
        .residual_program_ref = residual_ref,
        .closure_certificate_ref = closure_certificate_ref,
        .closure_graph_ref = closure_graph_ref,
        .closure_report_ref = closure_report_ref,
        .source_map_ref = source_map.evidenceRef(),
        .effect_row_ref = effect_row.evidenceRef(),
        .trace_map_ref = trace_map.evidenceRef(),
        .normal_form_ref = normal_form.evidenceRef(),
        .policy = intrinsic_blocking_policy,
        .normal_form = .world_ports_only,
        .selected_static_treaty_plan_refs = &.{ static_plan_ref, world_static_plan_ref },
        .world_port_refs = &.{world_port_ref},
        .residual_world_port_refs = &.{world_port_ref},
        .inlined_provider_program_refs = &.{provider_program_ref},
        .summary_counts = .{
            .root_effect_shapes = 2,
            .internal_routes_elaborated = 1,
            .provider_programs_linked = 1,
            .world_ports_emitted = 1,
        },
        .dependencies = dependencies[0..],
    });
    try std.testing.expectEqual(
        error.BoundaryElaborationWorldPortsRejected,
        intrinsic_blocking_certificate.check(intrinsic_blocking_policy, closure_graph_ref, closure_report_ref, closure_certificate_ref, source_map, effect_row, trace_map, normal_form, static_plans[0..], world_ports[0..]),
    );
    const constrained_world_port = Closure.WorldPort.init(.{
        .label = "approval.world.constrained",
        .kind = .test_fixture,
        .effect_shape_ref = world_shape_ref,
        .exposed_intrinsic_ref = intrinsic_ref,
        .supported_site_indexes = &.{5},
    });
    const constrained_world_port_ref = constrained_world_port.evidenceRef();
    var forged_residual_site_entries = source_entries;
    forged_residual_site_entries[1].residual_site_index = 6;
    forged_residual_site_entries[1].world_port_ref = constrained_world_port_ref;
    const forged_residual_site_map = Elaboration.SourceMap.init("runtime-agreement-forged-residual-site-map", forged_residual_site_entries[0..], &.{});
    const forged_residual_site_trace_entries = [_]Elaboration.TraceMap.Entry{
        trace_entries[0],
        .{ .source_ref = world_shape_ref, .residual_ref = constrained_world_port_ref, .trace_label = "approval.request.world.forged-residual-site" },
    };
    const forged_residual_site_trace = Elaboration.TraceMap.init("runtime-agreement-forged-residual-site-trace-map", forged_residual_site_trace_entries[0..]);
    const forged_residual_site_certificate = Elaboration.Certificate.init(.{
        .elaborated_program_label = "runtime-agreement-residual",
        .source_program_ref = source_ref,
        .residual_program_ref = residual_ref,
        .closure_certificate_ref = closure_certificate_ref,
        .closure_graph_ref = closure_graph_ref,
        .closure_report_ref = closure_report_ref,
        .source_map_ref = forged_residual_site_map.evidenceRef(),
        .effect_row_ref = effect_row.evidenceRef(),
        .trace_map_ref = forged_residual_site_trace.evidenceRef(),
        .normal_form_ref = normal_form.evidenceRef(),
        .policy = policy,
        .normal_form = .world_ports_only,
        .selected_static_treaty_plan_refs = &.{ static_plan_ref, world_static_plan_ref },
        .world_port_refs = &.{constrained_world_port_ref},
        .residual_world_port_refs = &.{constrained_world_port_ref},
        .inlined_provider_program_refs = &.{provider_program_ref},
        .summary_counts = .{
            .root_effect_shapes = 2,
            .internal_routes_elaborated = 1,
            .provider_programs_linked = 1,
            .world_ports_emitted = 1,
        },
        .dependencies = dependencies[0..],
    });
    try std.testing.expectEqual(
        error.BoundaryElaborationCertificateMismatch,
        forged_residual_site_certificate.check(policy, closure_graph_ref, closure_report_ref, closure_certificate_ref, forged_residual_site_map, effect_row, forged_residual_site_trace, normal_form, static_plans[0..], &.{constrained_world_port}),
    );
    var disallowed_world_policy = policy;
    disallowed_world_policy.closure_policy.allow_test_world_ports = false;
    const disallowed_world_ports = [_]u64{world_port_ref.fingerprint +% 1};
    disallowed_world_policy.closure_policy.allowed_world_port_fingerprints = disallowed_world_ports[0..];
    const disallowed_world_certificate = Elaboration.Certificate.init(.{
        .elaborated_program_label = "runtime-agreement-residual",
        .source_program_ref = source_ref,
        .residual_program_ref = residual_ref,
        .closure_certificate_ref = closure_certificate_ref,
        .closure_graph_ref = closure_graph_ref,
        .closure_report_ref = closure_report_ref,
        .source_map_ref = source_map.evidenceRef(),
        .effect_row_ref = effect_row.evidenceRef(),
        .trace_map_ref = trace_map.evidenceRef(),
        .normal_form_ref = normal_form.evidenceRef(),
        .policy = disallowed_world_policy,
        .normal_form = .world_ports_only,
        .selected_static_treaty_plan_refs = &.{ static_plan_ref, world_static_plan_ref },
        .world_port_refs = &.{world_port_ref},
        .residual_world_port_refs = &.{world_port_ref},
        .inlined_provider_program_refs = &.{provider_program_ref},
        .summary_counts = .{
            .root_effect_shapes = 2,
            .internal_routes_elaborated = 1,
            .provider_programs_linked = 1,
            .world_ports_emitted = 1,
        },
        .dependencies = dependencies[0..],
    });
    try std.testing.expectEqual(
        error.BoundaryElaborationWorldPortsRejected,
        disallowed_world_certificate.check(disallowed_world_policy, closure_graph_ref, closure_report_ref, closure_certificate_ref, source_map, effect_row, trace_map, normal_form, static_plans[0..], world_ports[0..]),
    );
    const untyped_intrinsic_ref = Evidence.refFor(Evidence.domains.host_intrinsic, 0xE1B00A, .{ .label = "approval.world.untyped" });
    const untyped_world_plan = Closure.StaticTreatyPlan.init(.{
        .label = "approval.world.untyped.plan",
        .source_shape = world_shape,
        .selected_semantic_body = .host_intrinsic,
        .selected_intrinsic_ref = untyped_intrinsic_ref,
        .host_intrinsic = true,
    });
    const untyped_world_port = Closure.WorldPort.init(.{
        .label = "approval.world.untyped",
        .kind = .test_fixture,
        .effect_shape_ref = world_shape_ref,
        .exposed_intrinsic_ref = untyped_intrinsic_ref,
    });
    var untyped_entries = source_entries;
    untyped_entries[1].static_treaty_plan_ref = untyped_world_plan.evidenceRef();
    untyped_entries[1].world_port_ref = untyped_world_port.evidenceRef();
    const untyped_map = Elaboration.SourceMap.init("runtime-agreement-untyped-intrinsic-map", untyped_entries[0..], &.{});
    const untyped_certificate = Elaboration.Certificate.init(.{
        .elaborated_program_label = "runtime-agreement-residual",
        .source_program_ref = source_ref,
        .residual_program_ref = residual_ref,
        .closure_certificate_ref = closure_certificate_ref,
        .closure_graph_ref = closure_graph_ref,
        .closure_report_ref = closure_report_ref,
        .source_map_ref = untyped_map.evidenceRef(),
        .effect_row_ref = effect_row.evidenceRef(),
        .trace_map_ref = trace_map.evidenceRef(),
        .normal_form_ref = normal_form.evidenceRef(),
        .policy = policy,
        .normal_form = .world_ports_only,
        .selected_static_treaty_plan_refs = &.{ static_plan_ref, untyped_world_plan.evidenceRef() },
        .world_port_refs = &.{untyped_world_port.evidenceRef()},
        .residual_world_port_refs = &.{untyped_world_port.evidenceRef()},
        .inlined_provider_program_refs = &.{provider_program_ref},
        .summary_counts = .{
            .root_effect_shapes = 2,
            .internal_routes_elaborated = 1,
            .provider_programs_linked = 1,
            .world_ports_emitted = 1,
        },
        .dependencies = dependencies[0..],
    });
    try std.testing.expectEqual(
        error.BoundaryElaborationCertificateMismatch,
        untyped_certificate.check(policy, closure_graph_ref, closure_report_ref, closure_certificate_ref, untyped_map, effect_row, trace_map, normal_form, &.{ static_plan, untyped_world_plan }, &.{untyped_world_port}),
    );
    var preserved_host_intrinsic_entries = source_entries;
    preserved_host_intrinsic_entries[1].residual_ref = residual_ref;
    preserved_host_intrinsic_entries[1].residual_site_index = null;
    preserved_host_intrinsic_entries[1].world_port_ref = null;
    preserved_host_intrinsic_entries[1].disposition = .preserved;
    const preserved_host_intrinsic_map = Elaboration.SourceMap.init("runtime-agreement-preserved-host-intrinsic-map", preserved_host_intrinsic_entries[0..], &.{});
    const preserved_host_intrinsic_trace_entries = [_]Elaboration.TraceMap.Entry{
        trace_entries[0],
        .{ .source_ref = world_shape_ref, .residual_ref = residual_ref, .trace_label = "approval.request.world.preserved" },
    };
    const preserved_host_intrinsic_trace = Elaboration.TraceMap.init("runtime-agreement-preserved-host-intrinsic-trace", preserved_host_intrinsic_trace_entries[0..]);
    const preserved_host_intrinsic_row = Elaboration.EffectRow.init(.{
        .label = "runtime-agreement-preserved-host-intrinsic-row",
        .source_program_ref = source_ref,
        .residual_program_ref = residual_ref,
        .normal_form = .strict_closed,
        .source_effect_shapes = 2,
        .closed_effect_shapes = 2,
        .provider_program_links = 1,
    });
    const preserved_host_intrinsic_normal = Elaboration.NormalForm.init("runtime-agreement-preserved-host-intrinsic-normal", .strict_closed, closure_certificate_ref, preserved_host_intrinsic_row.evidenceRef(), 0);
    const preserved_host_intrinsic_certificate = Elaboration.Certificate.init(.{
        .elaborated_program_label = "runtime-agreement-residual",
        .source_program_ref = source_ref,
        .residual_program_ref = residual_ref,
        .closure_certificate_ref = closure_certificate_ref,
        .closure_graph_ref = closure_graph_ref,
        .closure_report_ref = closure_report_ref,
        .source_map_ref = preserved_host_intrinsic_map.evidenceRef(),
        .effect_row_ref = preserved_host_intrinsic_row.evidenceRef(),
        .trace_map_ref = preserved_host_intrinsic_trace.evidenceRef(),
        .normal_form_ref = preserved_host_intrinsic_normal.evidenceRef(),
        .policy = policy,
        .normal_form = .strict_closed,
        .selected_static_treaty_plan_refs = &.{ static_plan_ref, world_static_plan_ref },
        .inlined_provider_program_refs = &.{provider_program_ref},
        .summary_counts = .{
            .root_effect_shapes = 2,
            .internal_routes_elaborated = 2,
            .provider_programs_linked = 1,
        },
        .dependencies = dependencies[0..],
    });
    try std.testing.expectEqual(
        error.BoundaryElaborationCertificateMismatch,
        preserved_host_intrinsic_certificate.check(policy, closure_graph_ref, closure_report_ref, closure_certificate_ref, preserved_host_intrinsic_map, preserved_host_intrinsic_row, preserved_host_intrinsic_trace, preserved_host_intrinsic_normal, static_plans[0..], world_ports[0..]),
    );
    const provider_world_port = Closure.WorldPort.init(.{
        .label = "approval.provider-as-world",
        .kind = .test_fixture,
        .effect_shape_ref = source_shape_ref,
        .exposed_intrinsic_ref = intrinsic_ref,
    });
    const provider_world_port_ref = provider_world_port.evidenceRef();
    const provider_as_world_entries = [_]Elaboration.SourceMap.Entry{
        .{
            .source_ref = source_shape_ref,
            .residual_ref = residual_ref,
            .source_site_index = 4,
            .residual_site_index = 4,
            .static_treaty_plan_ref = static_plan_ref,
            .world_port_ref = provider_world_port_ref,
            .disposition = .world_port_lowered,
            .label = "provider route downgraded to world port",
        },
        source_entries[1],
    };
    const provider_as_world_map = Elaboration.SourceMap.init("runtime-agreement-provider-as-world-map", provider_as_world_entries[0..], &.{});
    const provider_as_world_trace_entries = [_]Elaboration.TraceMap.Entry{
        .{ .source_ref = source_shape_ref, .residual_ref = provider_world_port_ref, .trace_label = "provider route downgraded to world port" },
        trace_entries[1],
    };
    const provider_as_world_trace = Elaboration.TraceMap.init("runtime-agreement-provider-as-world-trace", provider_as_world_trace_entries[0..]);
    const provider_as_world_row = Elaboration.EffectRow.init(.{
        .label = "runtime-agreement-provider-as-world-row",
        .source_program_ref = source_ref,
        .residual_program_ref = residual_ref,
        .normal_form = .world_ports_only,
        .source_effect_shapes = 2,
        .world_ports = 2,
    });
    const provider_as_world_normal = Elaboration.NormalForm.init("runtime-agreement-provider-as-world-normal", .world_ports_only, closure_certificate_ref, provider_as_world_row.evidenceRef(), 0);
    const provider_as_world_certificate = Elaboration.Certificate.init(.{
        .elaborated_program_label = "runtime-agreement-residual",
        .source_program_ref = source_ref,
        .residual_program_ref = residual_ref,
        .closure_certificate_ref = closure_certificate_ref,
        .closure_graph_ref = closure_graph_ref,
        .closure_report_ref = closure_report_ref,
        .source_map_ref = provider_as_world_map.evidenceRef(),
        .effect_row_ref = provider_as_world_row.evidenceRef(),
        .trace_map_ref = provider_as_world_trace.evidenceRef(),
        .normal_form_ref = provider_as_world_normal.evidenceRef(),
        .policy = policy,
        .normal_form = .world_ports_only,
        .selected_static_treaty_plan_refs = &.{ static_plan_ref, world_static_plan_ref },
        .world_port_refs = &.{ provider_world_port_ref, world_port_ref },
        .residual_world_port_refs = &.{ provider_world_port_ref, world_port_ref },
        .summary_counts = .{
            .root_effect_shapes = 2,
            .world_ports_emitted = 2,
        },
        .dependencies = dependencies[0..],
    });
    const provider_as_world_ports = [_]Closure.WorldPort{ provider_world_port, world_port };
    try std.testing.expectEqual(
        error.BoundaryElaborationWorldPortsRejected,
        provider_as_world_certificate.check(policy, closure_graph_ref, closure_report_ref, closure_certificate_ref, provider_as_world_map, provider_as_world_row, provider_as_world_trace, provider_as_world_normal, static_plans[0..], provider_as_world_ports[0..]),
    );
    var forged_route_entries = source_entries;
    forged_route_entries[0].provider_program_ref = null;
    forged_route_entries[0].disposition = .preserved;
    const forged_route_map = Elaboration.SourceMap.init("runtime-agreement-forged-route-map", forged_route_entries[0..], &.{});
    const forged_route_row = Elaboration.EffectRow.init(.{
        .label = "runtime-agreement-forged-route-row",
        .source_program_ref = source_ref,
        .residual_program_ref = residual_ref,
        .normal_form = .world_ports_only,
        .source_effect_shapes = 2,
        .closed_effect_shapes = 1,
        .world_ports = 1,
    });
    const forged_route_normal_form = Elaboration.NormalForm.init("runtime-agreement-forged-route-normal-form", .world_ports_only, closure_certificate_ref, forged_route_row.evidenceRef(), 0);
    const forged_route_certificate = Elaboration.Certificate.init(.{
        .elaborated_program_label = "runtime-agreement-residual",
        .source_program_ref = source_ref,
        .residual_program_ref = residual_ref,
        .closure_certificate_ref = closure_certificate_ref,
        .closure_graph_ref = closure_graph_ref,
        .closure_report_ref = closure_report_ref,
        .source_map_ref = forged_route_map.evidenceRef(),
        .effect_row_ref = forged_route_row.evidenceRef(),
        .trace_map_ref = trace_map.evidenceRef(),
        .normal_form_ref = forged_route_normal_form.evidenceRef(),
        .policy = policy,
        .normal_form = .world_ports_only,
        .selected_static_treaty_plan_refs = &.{ static_plan_ref, world_static_plan_ref },
        .world_port_refs = &.{world_port_ref},
        .residual_world_port_refs = &.{world_port_ref},
        .summary_counts = .{
            .root_effect_shapes = 2,
            .internal_routes_elaborated = 1,
            .world_ports_emitted = 1,
        },
        .dependencies = dependencies[0..],
    });
    try std.testing.expectEqual(
        error.BoundaryElaborationCertificateMismatch,
        forged_route_certificate.check(policy, closure_graph_ref, closure_report_ref, closure_certificate_ref, forged_route_map, forged_route_row, trace_map, forged_route_normal_form, static_plans[0..], world_ports[0..]),
    );
    var missing_residual_site_entries = source_entries;
    missing_residual_site_entries[1].residual_site_index = null;
    const missing_residual_site_map = Elaboration.SourceMap.init("runtime-agreement-missing-residual-site-map", missing_residual_site_entries[0..], &.{});
    const missing_residual_site_certificate = Elaboration.Certificate.init(.{
        .elaborated_program_label = "runtime-agreement-residual",
        .source_program_ref = source_ref,
        .residual_program_ref = residual_ref,
        .closure_certificate_ref = closure_certificate_ref,
        .closure_graph_ref = closure_graph_ref,
        .closure_report_ref = closure_report_ref,
        .source_map_ref = missing_residual_site_map.evidenceRef(),
        .effect_row_ref = effect_row.evidenceRef(),
        .trace_map_ref = trace_map.evidenceRef(),
        .normal_form_ref = normal_form.evidenceRef(),
        .policy = policy,
        .normal_form = .world_ports_only,
        .selected_static_treaty_plan_refs = &.{ static_plan_ref, world_static_plan_ref },
        .world_port_refs = &.{world_port_ref},
        .residual_world_port_refs = &.{world_port_ref},
        .inlined_provider_program_refs = &.{provider_program_ref},
        .summary_counts = .{
            .root_effect_shapes = 2,
            .internal_routes_elaborated = 1,
            .provider_programs_linked = 1,
            .world_ports_emitted = 1,
        },
        .dependencies = dependencies[0..],
    });
    try std.testing.expectEqual(
        error.BoundaryElaborationCertificateMismatch,
        missing_residual_site_certificate.check(policy, closure_graph_ref, closure_report_ref, closure_certificate_ref, missing_residual_site_map, effect_row, trace_map, normal_form, static_plans[0..], world_ports[0..]),
    );
    var missing_world_residual_entries = source_entries;
    missing_world_residual_entries[1].residual_ref = null;
    const missing_world_residual_map = Elaboration.SourceMap.init("runtime-agreement-missing-world-residual-map", missing_world_residual_entries[0..], &.{});
    const missing_world_residual_certificate = Elaboration.Certificate.init(.{
        .elaborated_program_label = "runtime-agreement-residual",
        .source_program_ref = source_ref,
        .residual_program_ref = residual_ref,
        .closure_certificate_ref = closure_certificate_ref,
        .closure_graph_ref = closure_graph_ref,
        .closure_report_ref = closure_report_ref,
        .source_map_ref = missing_world_residual_map.evidenceRef(),
        .effect_row_ref = effect_row.evidenceRef(),
        .trace_map_ref = trace_map.evidenceRef(),
        .normal_form_ref = normal_form.evidenceRef(),
        .policy = policy,
        .normal_form = .world_ports_only,
        .selected_static_treaty_plan_refs = &.{ static_plan_ref, world_static_plan_ref },
        .world_port_refs = &.{world_port_ref},
        .residual_world_port_refs = &.{world_port_ref},
        .inlined_provider_program_refs = &.{provider_program_ref},
        .summary_counts = .{
            .root_effect_shapes = 2,
            .internal_routes_elaborated = 1,
            .provider_programs_linked = 1,
            .world_ports_emitted = 1,
        },
        .dependencies = dependencies[0..],
    });
    try std.testing.expectEqual(
        error.BoundaryElaborationCertificateMismatch,
        missing_world_residual_certificate.check(policy, closure_graph_ref, closure_report_ref, closure_certificate_ref, missing_world_residual_map, effect_row, trace_map, normal_form, static_plans[0..], world_ports[0..]),
    );
    const duplicate_world_source_ref = Evidence.refFor(Evidence.domains.boundary_effect_shape, 0xE1B011, .{ .label = "approval.world.duplicate.source", .site_index = 5 });
    const second_world_port = Closure.WorldPort.init(.{
        .label = "approval.world.duplicate",
        .kind = .test_fixture,
        .effect_shape_ref = duplicate_world_source_ref,
    });
    const second_world_port_ref = second_world_port.evidenceRef();
    const duplicate_world_ports = [_]Closure.WorldPort{ world_port, second_world_port };
    const duplicate_site_entries = [_]Elaboration.SourceMap.Entry{
        source_entries[0],
        source_entries[1],
        .{
            .source_ref = duplicate_world_source_ref,
            .residual_ref = residual_ref,
            .source_site_index = 5,
            .residual_site_index = 4,
            .world_port_ref = second_world_port_ref,
            .disposition = .world_port_lowered,
            .label = "duplicate residual world port",
        },
    };
    const duplicate_site_map = Elaboration.SourceMap.init("runtime-agreement-duplicate-residual-site-map", duplicate_site_entries[0..], &.{});
    const duplicate_site_trace_entries = [_]Elaboration.TraceMap.Entry{
        trace_entries[0],
        trace_entries[1],
        .{ .source_ref = duplicate_world_source_ref, .residual_ref = second_world_port_ref, .trace_label = "approval.request.world.duplicate" },
    };
    const duplicate_site_trace_map = Elaboration.TraceMap.init("runtime-agreement-duplicate-residual-site-trace-map", duplicate_site_trace_entries[0..]);
    const duplicate_site_row = Elaboration.EffectRow.init(.{
        .label = "runtime-agreement-duplicate-site-row",
        .source_program_ref = source_ref,
        .residual_program_ref = residual_ref,
        .normal_form = .world_ports_only,
        .source_effect_shapes = 3,
        .closed_effect_shapes = 1,
        .provider_program_links = 1,
        .world_ports = 2,
    });
    const duplicate_site_normal_form = Elaboration.NormalForm.init("runtime-agreement-duplicate-site-normal-form", .world_ports_only, closure_certificate_ref, duplicate_site_row.evidenceRef(), 0);
    const duplicate_site_certificate = Elaboration.Certificate.init(.{
        .elaborated_program_label = "runtime-agreement-residual",
        .source_program_ref = source_ref,
        .residual_program_ref = residual_ref,
        .closure_certificate_ref = closure_certificate_ref,
        .closure_graph_ref = closure_graph_ref,
        .closure_report_ref = closure_report_ref,
        .source_map_ref = duplicate_site_map.evidenceRef(),
        .effect_row_ref = duplicate_site_row.evidenceRef(),
        .trace_map_ref = duplicate_site_trace_map.evidenceRef(),
        .normal_form_ref = duplicate_site_normal_form.evidenceRef(),
        .policy = policy,
        .normal_form = .world_ports_only,
        .selected_static_treaty_plan_refs = &.{static_plan_ref},
        .world_port_refs = &.{ world_port_ref, second_world_port_ref },
        .residual_world_port_refs = &.{ world_port_ref, second_world_port_ref },
        .inlined_provider_program_refs = &.{provider_program_ref},
        .summary_counts = .{
            .root_effect_shapes = 3,
            .internal_routes_elaborated = 1,
            .provider_programs_linked = 1,
            .world_ports_emitted = 2,
        },
        .dependencies = dependencies[0..],
    });
    try std.testing.expectEqual(
        error.BoundaryElaborationCertificateMismatch,
        duplicate_site_certificate.check(policy, closure_graph_ref, closure_report_ref, closure_certificate_ref, duplicate_site_map, duplicate_site_row, duplicate_site_trace_map, duplicate_site_normal_form, static_plans[0..], duplicate_world_ports[0..]),
    );
    const swapped_port_entries = [_]Elaboration.SourceMap.Entry{
        source_entries[0],
        .{
            .source_ref = source_shape_ref,
            .residual_ref = residual_ref,
            .source_site_index = 4,
            .residual_site_index = 4,
            .world_port_ref = second_world_port_ref,
            .disposition = .world_port_lowered,
            .label = "swapped world port lowering",
        },
        .{
            .source_ref = duplicate_world_source_ref,
            .residual_ref = residual_ref,
            .source_site_index = 5,
            .residual_site_index = 5,
            .world_port_ref = world_port_ref,
            .disposition = .world_port_lowered,
            .label = "swapped duplicate world port",
        },
    };
    const swapped_port_map = Elaboration.SourceMap.init("runtime-agreement-swapped-world-port-map", swapped_port_entries[0..], &.{});
    const swapped_port_trace_entries = [_]Elaboration.TraceMap.Entry{
        trace_entries[0],
        .{ .source_ref = source_shape_ref, .residual_ref = second_world_port_ref, .trace_label = "approval.request.world.swapped" },
        .{ .source_ref = duplicate_world_source_ref, .residual_ref = world_port_ref, .trace_label = "approval.request.world.duplicate.swapped" },
    };
    const swapped_port_trace_map = Elaboration.TraceMap.init("runtime-agreement-swapped-world-port-trace-map", swapped_port_trace_entries[0..]);
    const swapped_port_certificate = Elaboration.Certificate.init(.{
        .elaborated_program_label = "runtime-agreement-residual",
        .source_program_ref = source_ref,
        .residual_program_ref = residual_ref,
        .closure_certificate_ref = closure_certificate_ref,
        .closure_graph_ref = closure_graph_ref,
        .closure_report_ref = closure_report_ref,
        .source_map_ref = swapped_port_map.evidenceRef(),
        .effect_row_ref = duplicate_site_row.evidenceRef(),
        .trace_map_ref = swapped_port_trace_map.evidenceRef(),
        .normal_form_ref = duplicate_site_normal_form.evidenceRef(),
        .policy = policy,
        .normal_form = .world_ports_only,
        .selected_static_treaty_plan_refs = &.{static_plan_ref},
        .world_port_refs = &.{ world_port_ref, second_world_port_ref },
        .residual_world_port_refs = &.{ world_port_ref, second_world_port_ref },
        .inlined_provider_program_refs = &.{provider_program_ref},
        .summary_counts = .{
            .root_effect_shapes = 3,
            .internal_routes_elaborated = 1,
            .provider_programs_linked = 1,
            .world_ports_emitted = 2,
        },
        .dependencies = dependencies[0..],
    });
    try std.testing.expectEqual(
        error.BoundaryElaborationCertificateMismatch,
        swapped_port_certificate.check(policy, closure_graph_ref, closure_report_ref, closure_certificate_ref, swapped_port_map, duplicate_site_row, swapped_port_trace_map, duplicate_site_normal_form, static_plans[0..], duplicate_world_ports[0..]),
    );
    const extra_source_shape = Closure.EffectShape.init(.{
        .program_label = "source",
        .kind = .operation,
        .site_index = 5,
        .protocol_label = "approval",
    });
    const extra_source_shape_ref = extra_source_shape.evidenceRef();
    const extra_static_plan = Closure.StaticTreatyPlan.init(.{
        .label = "approval.extra.plan",
        .source_shape = extra_source_shape,
        .selected_semantic_body = .boundary_program,
        .selected_provider_program_ref = provider_program_ref,
    });
    const extra_static_plan_ref = extra_static_plan.evidenceRef();
    var forged_source_entries = source_entries;
    forged_source_entries[0].source_ref = extra_source_shape_ref;
    forged_source_entries[0].source_site_index = extra_source_shape.site_index;
    const forged_source_map = Elaboration.SourceMap.init("runtime-agreement-forged-source-map", forged_source_entries[0..], &.{});
    const forged_trace_entries = [_]Elaboration.TraceMap.Entry{
        .{ .source_ref = extra_source_shape_ref, .residual_ref = residual_ref, .trace_label = "approval.forged" },
        trace_entries[1],
    };
    const forged_trace_map = Elaboration.TraceMap.init("runtime-agreement-forged-source-trace-map", forged_trace_entries[0..]);
    const forged_source_certificate = Elaboration.Certificate.init(.{
        .elaborated_program_label = "runtime-agreement-residual",
        .source_program_ref = source_ref,
        .residual_program_ref = residual_ref,
        .closure_certificate_ref = closure_certificate_ref,
        .closure_graph_ref = closure_graph_ref,
        .closure_report_ref = closure_report_ref,
        .source_map_ref = forged_source_map.evidenceRef(),
        .effect_row_ref = effect_row.evidenceRef(),
        .trace_map_ref = forged_trace_map.evidenceRef(),
        .normal_form_ref = normal_form.evidenceRef(),
        .policy = policy,
        .normal_form = .world_ports_only,
        .selected_static_treaty_plan_refs = &.{static_plan_ref},
        .world_port_refs = &.{world_port_ref},
        .residual_world_port_refs = &.{world_port_ref},
        .inlined_provider_program_refs = &.{provider_program_ref},
        .summary_counts = .{
            .root_effect_shapes = 2,
            .internal_routes_elaborated = 1,
            .provider_programs_linked = 1,
            .world_ports_emitted = 1,
        },
        .dependencies = dependencies[0..],
    });
    try std.testing.expectEqual(
        error.BoundaryElaborationCertificateMismatch,
        forged_source_certificate.check(policy, closure_graph_ref, closure_report_ref, closure_certificate_ref, forged_source_map, effect_row, forged_trace_map, normal_form, static_plans[0..], world_ports[0..]),
    );
    const extra_source_entries = [_]Elaboration.SourceMap.Entry{
        source_entries[0],
        source_entries[1],
        .{
            .source_ref = extra_source_shape_ref,
            .residual_ref = residual_ref,
            .source_site_index = 5,
            .provider_program_ref = provider_program_ref,
            .static_treaty_plan_ref = extra_static_plan_ref,
            .disposition = .provider_program_linked,
            .label = "extra unaccounted route",
        },
    };
    const extra_source_map = Elaboration.SourceMap.init("runtime-agreement-extra-source-map", extra_source_entries[0..], &.{});
    const extra_trace_entries = [_]Elaboration.TraceMap.Entry{
        trace_entries[0],
        trace_entries[1],
        .{ .source_ref = extra_source_shape_ref, .residual_ref = residual_ref, .trace_label = "approval.extra" },
    };
    const extra_trace_map = Elaboration.TraceMap.init("runtime-agreement-extra-trace-map", extra_trace_entries[0..]);
    const extra_source_map_certificate = Elaboration.Certificate.init(.{
        .elaborated_program_label = "runtime-agreement-residual",
        .source_program_ref = source_ref,
        .residual_program_ref = residual_ref,
        .closure_certificate_ref = closure_certificate_ref,
        .closure_graph_ref = closure_graph_ref,
        .closure_report_ref = closure_report_ref,
        .source_map_ref = extra_source_map.evidenceRef(),
        .effect_row_ref = effect_row.evidenceRef(),
        .trace_map_ref = extra_trace_map.evidenceRef(),
        .normal_form_ref = normal_form.evidenceRef(),
        .policy = policy,
        .normal_form = .world_ports_only,
        .selected_static_treaty_plan_refs = &.{ static_plan_ref, extra_static_plan_ref },
        .world_port_refs = &.{world_port_ref},
        .residual_world_port_refs = &.{world_port_ref},
        .inlined_provider_program_refs = &.{ provider_program_ref, provider_program_ref },
        .summary_counts = .{
            .root_effect_shapes = 2,
            .internal_routes_elaborated = 1,
            .provider_programs_linked = 1,
            .world_ports_emitted = 1,
        },
        .dependencies = dependencies[0..],
    });
    try std.testing.expectEqual(
        error.BoundaryElaborationCertificateMismatch,
        extra_source_map_certificate.check(policy, closure_graph_ref, closure_report_ref, closure_certificate_ref, extra_source_map, effect_row, extra_trace_map, normal_form, static_plans[0..], world_ports[0..]),
    );
    const missing_static_refs_certificate = Elaboration.Certificate.init(.{
        .elaborated_program_label = "runtime-agreement-residual",
        .source_program_ref = source_ref,
        .residual_program_ref = residual_ref,
        .closure_certificate_ref = closure_certificate_ref,
        .closure_graph_ref = closure_graph_ref,
        .closure_report_ref = closure_report_ref,
        .source_map_ref = source_map.evidenceRef(),
        .effect_row_ref = effect_row.evidenceRef(),
        .trace_map_ref = trace_map.evidenceRef(),
        .normal_form_ref = normal_form.evidenceRef(),
        .policy = policy,
        .normal_form = .world_ports_only,
        .world_port_refs = &.{world_port_ref},
        .residual_world_port_refs = &.{world_port_ref},
        .inlined_provider_program_refs = &.{provider_program_ref},
        .summary_counts = .{
            .root_effect_shapes = 2,
            .internal_routes_elaborated = 1,
            .provider_programs_linked = 1,
            .world_ports_emitted = 1,
        },
        .dependencies = dependencies[0..],
    });
    try std.testing.expectEqual(
        error.BoundaryElaborationCertificateMismatch,
        missing_static_refs_certificate.check(policy, closure_graph_ref, closure_report_ref, closure_certificate_ref, source_map, effect_row, trace_map, normal_form, static_plans[0..], world_ports[0..]),
    );
    const missing_provider_refs_certificate = Elaboration.Certificate.init(.{
        .elaborated_program_label = "runtime-agreement-residual",
        .source_program_ref = source_ref,
        .residual_program_ref = residual_ref,
        .closure_certificate_ref = closure_certificate_ref,
        .closure_graph_ref = closure_graph_ref,
        .closure_report_ref = closure_report_ref,
        .source_map_ref = source_map.evidenceRef(),
        .effect_row_ref = effect_row.evidenceRef(),
        .trace_map_ref = trace_map.evidenceRef(),
        .normal_form_ref = normal_form.evidenceRef(),
        .policy = policy,
        .normal_form = .world_ports_only,
        .selected_static_treaty_plan_refs = &.{static_plan_ref},
        .world_port_refs = &.{world_port_ref},
        .residual_world_port_refs = &.{world_port_ref},
        .summary_counts = .{
            .root_effect_shapes = 2,
            .internal_routes_elaborated = 1,
            .provider_programs_linked = 1,
            .world_ports_emitted = 1,
        },
        .dependencies = dependencies[0..],
    });
    try std.testing.expectEqual(
        error.BoundaryElaborationCertificateMismatch,
        missing_provider_refs_certificate.check(policy, closure_graph_ref, closure_report_ref, closure_certificate_ref, source_map, effect_row, trace_map, normal_form, static_plans[0..], world_ports[0..]),
    );
    const stale_summary_certificate = Elaboration.Certificate.init(.{
        .elaborated_program_label = "runtime-agreement-residual",
        .source_program_ref = source_ref,
        .residual_program_ref = residual_ref,
        .closure_certificate_ref = closure_certificate_ref,
        .closure_graph_ref = closure_graph_ref,
        .closure_report_ref = closure_report_ref,
        .source_map_ref = source_map.evidenceRef(),
        .effect_row_ref = effect_row.evidenceRef(),
        .trace_map_ref = trace_map.evidenceRef(),
        .normal_form_ref = normal_form.evidenceRef(),
        .policy = policy,
        .normal_form = .world_ports_only,
        .selected_static_treaty_plan_refs = &.{static_plan_ref},
        .world_port_refs = &.{world_port_ref},
        .residual_world_port_refs = &.{world_port_ref},
        .inlined_provider_program_refs = &.{provider_program_ref},
        .summary_counts = .{
            .root_effect_shapes = 99,
            .internal_routes_elaborated = 1,
            .provider_programs_linked = 1,
            .world_ports_emitted = 1,
        },
        .dependencies = dependencies[0..],
    });
    try std.testing.expectEqual(
        error.BoundaryElaborationCertificateMismatch,
        stale_summary_certificate.check(policy, closure_graph_ref, closure_report_ref, closure_certificate_ref, source_map, effect_row, trace_map, normal_form, static_plans[0..], world_ports[0..]),
    );
    const omitted_summary_certificate = Elaboration.Certificate.init(.{
        .elaborated_program_label = "runtime-agreement-residual",
        .source_program_ref = source_ref,
        .residual_program_ref = residual_ref,
        .closure_certificate_ref = closure_certificate_ref,
        .closure_graph_ref = closure_graph_ref,
        .closure_report_ref = closure_report_ref,
        .source_map_ref = source_map.evidenceRef(),
        .effect_row_ref = effect_row.evidenceRef(),
        .trace_map_ref = trace_map.evidenceRef(),
        .normal_form_ref = normal_form.evidenceRef(),
        .policy = policy,
        .normal_form = .world_ports_only,
        .selected_static_treaty_plan_refs = &.{static_plan_ref},
        .world_port_refs = &.{world_port_ref},
        .residual_world_port_refs = &.{world_port_ref},
        .inlined_provider_program_refs = &.{provider_program_ref},
        .dependencies = dependencies[0..],
    });
    try std.testing.expectEqual(
        error.BoundaryElaborationCertificateMismatch,
        omitted_summary_certificate.check(policy, closure_graph_ref, closure_report_ref, closure_certificate_ref, source_map, effect_row, trace_map, normal_form, static_plans[0..], world_ports[0..]),
    );
    const missing_world_refs_certificate = Elaboration.Certificate.init(.{
        .elaborated_program_label = "runtime-agreement-residual",
        .source_program_ref = source_ref,
        .residual_program_ref = residual_ref,
        .closure_certificate_ref = closure_certificate_ref,
        .closure_graph_ref = closure_graph_ref,
        .closure_report_ref = closure_report_ref,
        .source_map_ref = source_map.evidenceRef(),
        .effect_row_ref = effect_row.evidenceRef(),
        .trace_map_ref = trace_map.evidenceRef(),
        .normal_form_ref = normal_form.evidenceRef(),
        .policy = policy,
        .normal_form = .world_ports_only,
        .selected_static_treaty_plan_refs = &.{static_plan_ref},
        .inlined_provider_program_refs = &.{provider_program_ref},
        .summary_counts = .{
            .root_effect_shapes = 2,
            .internal_routes_elaborated = 1,
            .provider_programs_linked = 1,
            .world_ports_emitted = 1,
        },
        .dependencies = dependencies[0..],
    });
    try std.testing.expectEqual(
        error.BoundaryElaborationCertificateMismatch,
        missing_world_refs_certificate.check(policy, closure_graph_ref, closure_report_ref, closure_certificate_ref, source_map, effect_row, trace_map, normal_form, static_plans[0..], world_ports[0..]),
    );
    try std.testing.expectEqual(Evidence.domains.boundary_elaboration_certificate.id, elaboration_certificate.evidenceView().domain);
}

test "morphism pipeline elaboration blockers are fail closed" {
    const Elaboration = Program.BoundaryClosure.Elaboration;
    const shape_ref = Evidence.refFor(Evidence.domains.boundary_effect_shape, 0xE1C001, .{ .label = "approval.request" });
    const morphism_ref = Evidence.refFor(Evidence.domains.morphism_offer, 0xE1C002, .{ .label = "dynamic-mapper" });
    const pipeline_ref = Evidence.refFor(Evidence.domains.pipeline, 0xE1C003, .{ .label = "missing-pipeline" });
    const blockers = [_]Elaboration.Blocker{
        .{
            .tag = .dynamic_mapper_not_elaborable,
            .subject = shape_ref,
            .primary = morphism_ref,
            .summary = "dynamic host mapper is not elaborable",
        },
        .{
            .tag = .pipeline_adapter_missing,
            .subject = shape_ref,
            .primary = pipeline_ref,
            .summary = "pipeline adapter evidence is missing",
        },
    };
    const first = blockers[0].toEvidenceBlocker();
    const second = blockers[1].toEvidenceBlocker();
    try std.testing.expect(first.valid());
    try std.testing.expect(second.valid());
    try std.testing.expectEqualStrings("dynamic_mapper_not_elaborable", first.short_code);
    try std.testing.expectEqualStrings("pipeline_adapter_missing", second.short_code);
    try std.testing.expect(Evidence.refForBoundaryElaborationBlocker(first).kind_tag != null);
    try std.testing.expect(Evidence.refForBoundaryElaborationBlocker(second).kind_tag != null);
}

test "boundary elaboration input validation rejects duplicate provider proof refs" {
    const Closure = Program.BoundaryClosure;
    const Elaboration = Closure.Elaboration;
    const source_ref = comptime Evidence.refFor(Evidence.domains.program_plan, Program.compiled_plan.hash(), .{ .label = Program.contract.label });
    const provider_a_ref = Evidence.refFor(Evidence.domains.program_plan, 0xE1D102, .{ .label = "provider-a" });
    const provider_b_ref = Evidence.refFor(Evidence.domains.program_plan, 0xE1D103, .{ .label = "provider-b" });
    const graph = Closure.Graph.init("duplicate-provider-proof-graph", &.{}, &.{}, &.{});
    const provider_refs = [_]Evidence.Ref{ provider_a_ref, provider_b_ref };
    const report = Closure.Report.init(.{
        .graph_fingerprint = graph.fingerprint,
        .root_program_refs = &.{source_ref},
        .provider_program_refs = provider_refs[0..],
    });
    const certificate = Closure.Certificate.init(report, graph, Closure.Policy.auditOnly(), &.{});
    const duplicate_programs = [_]Closure.ProviderProgram{
        .{ .provider_ref = provider_a_ref, .program_ref = provider_a_ref, .effect_free = true },
        .{ .provider_ref = provider_a_ref, .program_ref = provider_a_ref, .effect_free = true },
    };
    const policy = Elaboration.Policy.auditOnly();
    const input = Elaboration.Input{
        .closure_graph = graph,
        .closure_report = report,
        .closure_certificate = certificate,
        .source_program_ref = source_ref,
        .provider_programs = duplicate_programs[0..],
        .policy = policy,
    };
    try std.testing.expectEqual(error.BoundaryElaborationProviderProgramRefMismatch, input.validate());

    const duplicated_report_refs = [_]Evidence.Ref{ provider_a_ref, provider_a_ref };
    const duplicated_report = Closure.Report.init(.{
        .graph_fingerprint = graph.fingerprint,
        .root_program_refs = &.{source_ref},
        .provider_program_refs = duplicated_report_refs[0..],
    });
    const duplicated_certificate = Closure.Certificate.init(duplicated_report, graph, Closure.Policy.auditOnly(), &.{});
    const duplicated_input = Elaboration.Input{
        .closure_graph = graph,
        .closure_report = duplicated_report,
        .closure_certificate = duplicated_certificate,
        .source_program_ref = source_ref,
        .provider_programs = duplicate_programs[0..],
        .policy = policy,
    };
    try std.testing.expectEqual(error.BoundaryElaborationProviderProgramRefMismatch, duplicated_input.validate());

    const alternate_provider_ref = Evidence.refFor(Evidence.domains.provider_manifest, 0xE1D109, .{ .label = "alternate-provider" });
    const repeated_program_ref_report = Closure.Report.init(.{
        .graph_fingerprint = graph.fingerprint,
        .root_program_refs = &.{source_ref},
        .provider_program_refs = &.{provider_a_ref},
    });
    const repeated_program_ref_certificate = Closure.Certificate.init(repeated_program_ref_report, graph, Closure.Policy.auditOnly(), &.{});
    const repeated_program_ref_proofs = [_]Closure.ProviderProgram{
        .{ .provider_ref = provider_a_ref, .program_ref = provider_a_ref, .provider_program_mapping_fingerprint = 0xE1D1_0901, .request_mapping = .payload_to_args, .result_mapping = .result_to_resume, .effect_free = true },
        .{ .provider_ref = alternate_provider_ref, .program_ref = provider_a_ref, .provider_program_mapping_fingerprint = 0xE1D1_0902, .request_mapping = .payload_to_args, .result_mapping = .result_to_resume, .effect_free = true },
    };
    const repeated_program_ref_input = Elaboration.Input{
        .closure_graph = graph,
        .closure_report = repeated_program_ref_report,
        .closure_certificate = repeated_program_ref_certificate,
        .source_program_ref = source_ref,
        .provider_programs = repeated_program_ref_proofs[0..],
        .policy = policy,
    };
    try repeated_program_ref_input.validate();

    const provider_ref = Evidence.refFor(Evidence.domains.provider_manifest, 0xE1D104, .{ .label = "provider" });
    const provider_program_ref = Evidence.refFor(Evidence.domains.program_plan, 0xE1D105, .{ .label = "provider-program" });
    const source_shape = Closure.EffectShape.init(.{
        .program_label = "source",
        .kind = .operation,
        .site_index = 0,
        .protocol_label = "approval",
        .expected_resume_ref = Evidence.BoundaryValueRef.init("unit", null),
    });
    const nested_shape = Closure.EffectShape.init(.{
        .program_label = "provider-program",
        .plan_hash = provider_program_ref.fingerprint,
        .kind = .operation,
        .site_index = 0,
        .protocol_label = "policy",
    });
    const provider_plan = Closure.StaticTreatyPlan.init(.{
        .label = "provider-program-plan",
        .source_shape = source_shape,
        .selected_provider_ref = provider_ref,
        .selected_provider_offer_ref = provider_ref,
        .selected_capability_ref = provider_ref,
        .selected_semantic_body = .boundary_program,
        .selected_provider_program_ref = provider_program_ref,
        .selected_provider_program_mapping_fingerprint = 0xE1D1_0501,
        .selected_provider_program_request_mapping_tag = "payload_to_args",
        .selected_provider_program_result_mapping_tag = "result_to_resume",
        .selected_provider_program_effect_shape_count = 1,
        .selected_provider_program_effect_shape_fingerprint = Evidence.fingerprintBoundaryEffectShapeSet(&.{nested_shape}),
    });
    const shape_mismatch_report = Closure.Report.init(.{
        .graph_fingerprint = graph.fingerprint,
        .root_program_refs = &.{source_ref},
        .provider_program_refs = &.{provider_program_ref},
    });
    const shape_mismatch_certificate = Closure.Certificate.init(shape_mismatch_report, graph, Closure.Policy.auditOnly(), &.{provider_plan.evidenceRef()});
    const shape_mismatch_programs = [_]Closure.ProviderProgram{.{
        .provider_ref = provider_ref,
        .program_ref = provider_program_ref,
        .provider_program_mapping_fingerprint = provider_plan.selected_provider_program_mapping_fingerprint,
        .request_mapping = .payload_to_args,
        .result_mapping = .result_to_resume,
        .effect_free = true,
    }};
    const shape_mismatch_input = Elaboration.Input{
        .closure_graph = graph,
        .closure_report = shape_mismatch_report,
        .closure_certificate = shape_mismatch_certificate,
        .static_treaty_plans = &.{provider_plan},
        .source_program_ref = source_ref,
        .provider_programs = shape_mismatch_programs[0..],
        .policy = policy,
    };
    try std.testing.expectEqual(error.BoundaryElaborationProviderProgramRefMismatch, shape_mismatch_input.validate());

    const pipeline_morphism_ref = Evidence.refFor(Evidence.domains.morphism_offer, 0xE1D107, .{ .label = "provider-pipeline-morphism" });
    const pipeline_adapter_ref = Evidence.refFor(Evidence.domains.pipeline, 0xE1D108, .{ .label = "provider-pipeline-adapter" });
    const pipeline_morphism_dependencies = [_]Evidence.Dependency{
        .{ .role = .morphism, .ref = pipeline_morphism_ref },
        .{ .role = .pipeline, .ref = pipeline_adapter_ref },
    };
    const provider_pipeline_plan = Closure.StaticTreatyPlan.init(.{
        .label = "provider-pipeline-route",
        .source_shape = source_shape,
        .selected_provider_ref = provider_ref,
        .selected_provider_offer_ref = provider_ref,
        .selected_capability_ref = provider_ref,
        .selected_semantic_body = .boundary_program,
        .selected_morphism_ref = pipeline_morphism_ref,
        .selected_morphism_semantic_body = .pipeline,
        .selected_provider_program_ref = provider_program_ref,
        .selected_provider_program_mapping_fingerprint = provider_plan.selected_provider_program_mapping_fingerprint,
        .selected_provider_program_request_mapping_tag = "payload_to_args",
        .selected_provider_program_result_mapping_tag = "result_to_resume",
        .selected_provider_program_effect_shape_count = provider_plan.selected_provider_program_effect_shape_count,
        .selected_provider_program_effect_shape_fingerprint = provider_plan.selected_provider_program_effect_shape_fingerprint,
        .dependencies = pipeline_morphism_dependencies[0..],
    });
    const provider_pipeline_certificate = Closure.Certificate.init(shape_mismatch_report, graph, Closure.Policy.auditOnly(), &.{provider_pipeline_plan.evidenceRef()});
    const matching_provider_programs = [_]Closure.ProviderProgram{.{
        .provider_ref = provider_ref,
        .program_ref = provider_program_ref,
        .provider_program_mapping_fingerprint = provider_plan.selected_provider_program_mapping_fingerprint,
        .provider_program_mapping_support_fingerprint = Closure.providerProgramMappingSupportFingerprintForPlan(provider_pipeline_plan, .payload_to_args, .result_to_resume),
        .request_mapping = .payload_to_args,
        .result_mapping = .result_to_resume,
        .shapes = &.{nested_shape},
    }};
    var provider_pipeline_policy = Elaboration.Policy.auditOnly();
    provider_pipeline_policy.require_program_backed_providers_for_internal_routes = false;
    provider_pipeline_policy.allow_pipeline_adapters = false;
    const provider_pipeline_input = Elaboration.Input{
        .closure_graph = graph,
        .closure_report = shape_mismatch_report,
        .closure_certificate = provider_pipeline_certificate,
        .static_treaty_plans = &.{provider_pipeline_plan},
        .source_program_ref = source_ref,
        .provider_programs = matching_provider_programs[0..],
        .policy = provider_pipeline_policy,
    };
    try std.testing.expectEqual(error.BoundaryElaborationProviderProgramRefMismatch, provider_pipeline_input.validate());

    var blocker_policy = Elaboration.Policy.auditOnly();
    blocker_policy.max_blockers = 1;
    const capped_report = Closure.Report.init(.{
        .graph_fingerprint = graph.fingerprint,
        .root_program_refs = &.{source_ref},
        .blocker_count = 2,
    });
    const capped_certificate = Closure.Certificate.init(capped_report, graph, Closure.Policy.auditOnly(), &.{});
    const capped_input = Elaboration.Input{
        .closure_graph = graph,
        .closure_report = capped_report,
        .closure_certificate = capped_certificate,
        .source_program_ref = source_ref,
        .policy = blocker_policy,
    };
    try std.testing.expectEqual(error.BoundaryElaborationBlocked, capped_input.validate());

    var unsupported_blocker_policy = Elaboration.Policy.auditOnly();
    unsupported_blocker_policy.fail_on_unsupported_shape = true;
    unsupported_blocker_policy.max_blockers = 1;
    const non_unsupported_blocker = Evidence.boundaryClosureBlocker(.{
        .tag = .cycle_detected,
        .subject = source_ref,
        .summary = "provider traversal cycle",
    });
    const non_unsupported_report = Closure.Report.init(.{
        .graph_fingerprint = graph.fingerprint,
        .root_program_refs = &.{source_ref},
        .blockers = &.{non_unsupported_blocker},
    });
    const non_unsupported_input = Elaboration.Input{
        .closure_graph = graph,
        .closure_report = non_unsupported_report,
        .closure_certificate = Closure.Certificate.init(non_unsupported_report, graph, Closure.Policy.auditOnly(), &.{}),
        .source_program_ref = source_ref,
        .policy = unsupported_blocker_policy,
    };
    try non_unsupported_input.validate();

    const unsupported_shape_blocker = Evidence.boundaryClosureBlocker(.{
        .tag = .unsupported_shape_planning,
        .subject = source_shape.evidenceRef(),
        .summary = "unsupported shape",
    });
    const unsupported_shape_report = Closure.Report.init(.{
        .graph_fingerprint = graph.fingerprint,
        .root_program_refs = &.{source_ref},
        .blockers = &.{unsupported_shape_blocker},
    });
    const unsupported_shape_input = Elaboration.Input{
        .closure_graph = graph,
        .closure_report = unsupported_shape_report,
        .closure_certificate = Closure.Certificate.init(unsupported_shape_report, graph, Closure.Policy.auditOnly(), &.{}),
        .source_program_ref = source_ref,
        .policy = unsupported_blocker_policy,
    };
    try std.testing.expectEqual(error.BoundaryElaborationBlocked, unsupported_shape_input.validate());

    const intrinsic_ref = Evidence.refFor(Evidence.domains.host_intrinsic, 0xE1D106, .{ .label = "host.approval" });
    const intrinsic_plan = Closure.StaticTreatyPlan.init(.{
        .label = "host-intrinsic-route",
        .source_shape = source_shape,
        .selected_provider_ref = provider_ref,
        .selected_provider_offer_ref = provider_ref,
        .selected_capability_ref = provider_ref,
        .selected_semantic_body = .host_intrinsic,
        .selected_intrinsic_ref = intrinsic_ref,
    });
    const intrinsic_report = Closure.Report.init(.{
        .graph_fingerprint = graph.fingerprint,
        .root_program_refs = &.{source_ref},
    });
    const intrinsic_certificate = Closure.Certificate.init(intrinsic_report, graph, Closure.Policy.auditOnly(), &.{intrinsic_plan.evidenceRef()});
    const intrinsic_input = Elaboration.Input{
        .closure_graph = graph,
        .closure_report = intrinsic_report,
        .closure_certificate = intrinsic_certificate,
        .static_treaty_plans = &.{intrinsic_plan},
        .source_program_ref = source_ref,
        .policy = policy,
    };
    try std.testing.expectEqual(error.BoundaryElaborationWorldPortRefMismatch, intrinsic_input.validate());

    const constrained_intrinsic_port = Closure.WorldPort.init(.{
        .label = "constrained-host-intrinsic-world-port",
        .kind = .test_fixture,
        .exposed_intrinsic_ref = intrinsic_ref,
        .supported_protocol_labels = &.{"approval"},
        .supported_site_indexes = &.{0},
    });
    const constrained_intrinsic_report = Closure.Report.init(.{
        .graph_fingerprint = graph.fingerprint,
        .root_program_refs = &.{source_ref},
        .world_port_refs = &.{constrained_intrinsic_port.evidenceRef()},
        .open_world_port_count = 1,
    });
    const constrained_intrinsic_certificate = Closure.Certificate.init(constrained_intrinsic_report, graph, Closure.Policy.auditOnly(), &.{intrinsic_plan.evidenceRef()});
    const constrained_intrinsic_input = Elaboration.Input{
        .closure_graph = graph,
        .closure_report = constrained_intrinsic_report,
        .closure_certificate = constrained_intrinsic_certificate,
        .static_treaty_plans = &.{intrinsic_plan},
        .source_program_ref = source_ref,
        .world_ports = &.{constrained_intrinsic_port},
        .policy = Elaboration.Policy.auditOnly(),
    };
    try constrained_intrinsic_input.validate();

    const intrinsic_subject_alias_ref = Evidence.refFor(Evidence.domains.host_intrinsic, intrinsic_ref.fingerprint, .{ .label = "host.approval.alias" });
    const shape_subject_alias_ref = Evidence.refFor(Evidence.domains.boundary_effect_shape, source_shape.fingerprint, .{
        .label = "source-shape-alias",
        .site_index = 0,
        .kind_tag = "operation",
    });
    const subject_alias_intrinsic_port = Closure.WorldPort.init(.{
        .label = "subject-alias-host-intrinsic-world-port",
        .kind = .test_fixture,
        .effect_shape_ref = shape_subject_alias_ref,
        .exposed_intrinsic_ref = intrinsic_subject_alias_ref,
        .supported_protocol_labels = &.{"approval"},
        .supported_site_indexes = &.{0},
    });
    const subject_alias_intrinsic_report = Closure.Report.init(.{
        .graph_fingerprint = graph.fingerprint,
        .root_program_refs = &.{source_ref},
        .world_port_refs = &.{subject_alias_intrinsic_port.evidenceRef()},
        .open_world_port_count = 1,
    });
    const subject_alias_intrinsic_input = Elaboration.Input{
        .closure_graph = graph,
        .closure_report = subject_alias_intrinsic_report,
        .closure_certificate = Closure.Certificate.init(subject_alias_intrinsic_report, graph, Closure.Policy.auditOnly(), &.{intrinsic_plan.evidenceRef()}),
        .static_treaty_plans = &.{intrinsic_plan},
        .source_program_ref = source_ref,
        .world_ports = &.{subject_alias_intrinsic_port},
        .policy = Elaboration.Policy.auditOnly(),
    };
    try subject_alias_intrinsic_input.validate();

    const non_host_intrinsic_ref = Evidence.refFor(Evidence.domains.program_plan, 0xE1D10C, .{ .kind_tag = "provider_function" });
    const non_host_intrinsic_plan = Closure.StaticTreatyPlan.init(.{
        .label = "non-host-intrinsic-route",
        .source_shape = source_shape,
        .selected_provider_ref = provider_ref,
        .selected_provider_offer_ref = provider_ref,
        .selected_capability_ref = provider_ref,
        .selected_semantic_body = .host_intrinsic,
        .selected_intrinsic_ref = non_host_intrinsic_ref,
    });
    const non_host_intrinsic_port = Closure.WorldPort.init(.{
        .label = "non-host-intrinsic-world-port",
        .kind = .test_fixture,
        .exposed_intrinsic_ref = non_host_intrinsic_ref,
        .supported_protocol_labels = &.{"approval"},
        .supported_site_indexes = &.{0},
    });
    const non_host_intrinsic_report = Closure.Report.init(.{
        .graph_fingerprint = graph.fingerprint,
        .root_program_refs = &.{source_ref},
        .world_port_refs = &.{non_host_intrinsic_port.evidenceRef()},
        .open_world_port_count = 1,
    });
    const non_host_intrinsic_input = Elaboration.Input{
        .closure_graph = graph,
        .closure_report = non_host_intrinsic_report,
        .closure_certificate = Closure.Certificate.init(non_host_intrinsic_report, graph, Closure.Policy.auditOnly(), &.{non_host_intrinsic_plan.evidenceRef()}),
        .static_treaty_plans = &.{non_host_intrinsic_plan},
        .source_program_ref = source_ref,
        .world_ports = &.{non_host_intrinsic_port},
        .policy = Elaboration.Policy.auditOnly(),
    };
    try std.testing.expectEqual(error.BoundaryElaborationBlocked, non_host_intrinsic_input.validate());

    const morphism_intrinsic_ref = Evidence.refFor(Evidence.domains.host_intrinsic, 0xE1D10A, .{ .label = "host.morphism.approval" });
    const morphism_intrinsic_plan = Closure.StaticTreatyPlan.init(.{
        .label = "host-intrinsic-morphism-route",
        .source_shape = source_shape,
        .selected_provider_ref = provider_ref,
        .selected_provider_offer_ref = provider_ref,
        .selected_capability_ref = provider_ref,
        .selected_semantic_body = .declarative,
        .selected_morphism_ref = Evidence.refFor(Evidence.domains.morphism_offer, 0xE1D10B, .{ .label = "host-intrinsic-morphism" }),
        .selected_morphism_semantic_body = .host_intrinsic,
        .selected_morphism_intrinsic_ref = morphism_intrinsic_ref,
    });
    const morphism_intrinsic_certificate = Closure.Certificate.init(intrinsic_report, graph, Closure.Policy.auditOnly(), &.{morphism_intrinsic_plan.evidenceRef()});
    const morphism_intrinsic_input = Elaboration.Input{
        .closure_graph = graph,
        .closure_report = intrinsic_report,
        .closure_certificate = morphism_intrinsic_certificate,
        .static_treaty_plans = &.{morphism_intrinsic_plan},
        .source_program_ref = source_ref,
        .policy = policy,
    };
    try std.testing.expectEqual(error.BoundaryElaborationBlocked, morphism_intrinsic_input.validate());

    const target_shape_world_port_ok = comptime blk: {
        @setEvalBranchQuota(200_000);
        const target_shape_pipeline_morphism = Program.Exchange.MorphismOffer{
            .label = "provider-pipeline-morphism",
            .target_protocol_op_fingerprint = 0xE1D1_0D01,
            .pipeline_fingerprint = 0xE1D108,
        };
        const target_shape_pipeline_morphism_ref = target_shape_pipeline_morphism.evidenceRef();
        const target_shape_pipeline_adapter_ref = Evidence.refFor(Evidence.domains.pipeline, target_shape_pipeline_morphism.pipeline_fingerprint.?, .{ .label = "provider-pipeline-adapter" });
        const target_source_ref = Evidence.refFor(Evidence.domains.program_plan, Program.compiled_plan.hash(), .{ .label = Program.contract.label });
        const target_graph = Closure.Graph.init("morphism-target-shape-graph", &.{}, &.{}, &.{});
        const target_source_shape = Closure.EffectShape.init(.{
            .program_label = "source",
            .kind = .operation,
            .site_index = 0,
            .protocol_label = "approval",
            .expected_resume_ref = Evidence.BoundaryValueRef.init("unit", null),
        });
        const morphism_target_shape = Closure.EffectShape.init(.{
            .program_label = "source",
            .kind = .operation,
            .site_index = 0,
            .protocol_label = "approval",
            .protocol_op_fingerprint = 0xE1D1_0D01,
            .expected_resume_ref = Evidence.BoundaryValueRef.init("unit", null),
            .usage_summary = "copyable",
        });
        const morphism_target_shape_alias_ref = Evidence.refFor(Evidence.domains.boundary_effect_shape, morphism_target_shape.fingerprint, .{
            .label = "morphism-target-alias",
            .site_index = 0,
            .kind_tag = "operation",
        });
        const target_shape_world_port = Closure.WorldPort.init(.{
            .label = "morphism-target-shape-world-port",
            .kind = .test_fixture,
            .effect_shape_ref = morphism_target_shape_alias_ref,
            .supported_protocol_labels = &.{"approval"},
            .supported_site_indexes = &.{0},
        });
        const target_shape_morphism_dependencies = [_]Evidence.Dependency{
            .{ .role = .morphism, .ref = target_shape_pipeline_morphism_ref },
            .{ .role = .pipeline, .ref = target_shape_pipeline_adapter_ref },
        };
        const target_shape_morphism_plan = Closure.StaticTreatyPlan.init(.{
            .label = "morphism-target-shape-route",
            .source_shape = target_source_shape,
            .selected_semantic_body = .declarative,
            .selected_morphism_ref = target_shape_pipeline_morphism_ref,
            .selected_morphism_target_shape_ref = morphism_target_shape_alias_ref,
            .selected_morphism_target_shape = morphism_target_shape,
            .selected_morphism_semantic_body = .pipeline,
            .dependencies = target_shape_morphism_dependencies[0..],
        });
        const target_shape_report = Closure.Report.init(.{
            .graph_fingerprint = target_graph.fingerprint,
            .root_program_refs = &.{target_source_ref},
            .effect_shape_count = 1,
            .world_port_refs = &.{target_shape_world_port.evidenceRef()},
            .open_world_port_count = 1,
        });
        var target_shape_policy = Elaboration.Policy.auditOnly();
        target_shape_policy.allow_pipeline_adapters = true;
        const target_shape_input = Elaboration.Input{
            .closure_graph = target_graph,
            .closure_report = target_shape_report,
            .closure_certificate = Closure.Certificate.init(target_shape_report, target_graph, Closure.Policy.auditOnly(), &.{target_shape_morphism_plan.evidenceRef()}),
            .static_treaty_plans = &.{target_shape_morphism_plan},
            .source_program_ref = target_source_ref,
            .world_ports = &.{target_shape_world_port},
            .morphism_offers = &.{target_shape_pipeline_morphism},
            .morphism_offer_refs = &.{target_shape_pipeline_morphism_ref},
            .pipeline_adapter_refs = &.{target_shape_pipeline_adapter_ref},
            .policy = target_shape_policy,
        };
        const TargetShapeBody = Elaboration.FromResidual(target_shape_input, closure_source_program, .{ .label = "morphism-target-shape-body" });
        const positive_ok = TargetShapeBody.source_map.entries[0].source_ref.eql(morphism_target_shape_alias_ref) and
            TargetShapeBody.source_map.entries[0].world_port_ref.?.eql(target_shape_world_port.evidenceRef());

        const offered_target_shape = Closure.EffectShape.init(.{
            .program_label = "offered-morphism-target",
            .kind = .operation,
            .site_index = 0,
            .protocol_label = "approval",
            .protocol_op_fingerprint = 0xE1D1_0D02,
            .usage_summary = "copyable",
        });
        const forged_target_shape = Closure.EffectShape.init(.{
            .program_label = "forged-morphism-target",
            .kind = .operation,
            .site_index = 0,
            .protocol_label = "approval",
            .protocol_op_fingerprint = 0xE1D1_0D03,
            .usage_summary = "copyable",
        });
        const checked_morphism = Program.Exchange.MorphismOffer{
            .label = "checked-target-shape-morphism",
            .target_protocol_op_fingerprint = 0xE1D1_0D02,
            .pipeline_fingerprint = 0xE1D1_0D04,
        };
        const checked_pipeline_ref = Evidence.refFor(Evidence.domains.pipeline, checked_morphism.pipeline_fingerprint.?, .{ .label = "checked-target-shape-pipeline" });
        const forged_target_shape_port = Closure.WorldPort.init(.{
            .label = "forged-morphism-target-shape-world-port",
            .kind = .test_fixture,
            .effect_shape_ref = forged_target_shape.evidenceRef(),
            .supported_protocol_labels = &.{"approval"},
            .supported_site_indexes = &.{0},
        });
        const forged_target_shape_dependencies = [_]Evidence.Dependency{
            .{ .role = .morphism, .ref = checked_morphism.evidenceRef() },
            .{ .role = .pipeline, .ref = checked_pipeline_ref },
        };
        const forged_target_shape_plan = Closure.StaticTreatyPlan.init(.{
            .label = "forged-morphism-target-shape-route",
            .source_shape = target_source_shape,
            .selected_semantic_body = .declarative,
            .selected_morphism_ref = checked_morphism.evidenceRef(),
            .selected_morphism_target_shape_ref = forged_target_shape.evidenceRef(),
            .selected_morphism_target_shape = forged_target_shape,
            .selected_morphism_semantic_body = .pipeline,
            .dependencies = forged_target_shape_dependencies[0..],
        });
        const forged_target_shape_report = Closure.Report.init(.{
            .graph_fingerprint = target_graph.fingerprint,
            .root_program_refs = &.{target_source_ref},
            .effect_shape_count = 1,
            .world_port_refs = &.{forged_target_shape_port.evidenceRef()},
            .open_world_port_count = 1,
        });
        const forged_target_shape_input = Elaboration.Input{
            .closure_graph = target_graph,
            .closure_report = forged_target_shape_report,
            .closure_certificate = Closure.Certificate.init(forged_target_shape_report, target_graph, Closure.Policy.auditOnly(), &.{forged_target_shape_plan.evidenceRef()}),
            .static_treaty_plans = &.{forged_target_shape_plan},
            .source_program_ref = target_source_ref,
            .world_ports = &.{forged_target_shape_port},
            .morphism_offers = &.{checked_morphism},
            .morphism_offer_refs = &.{checked_morphism.evidenceRef()},
            .pipeline_adapter_refs = &.{checked_pipeline_ref},
            .policy = Elaboration.Policy.auditOnly(),
        };
        const forged_rejected = reject: {
            forged_target_shape_input.validateResidualProgram(closure_source_program) catch |err| {
                break :reject err == error.BoundaryElaborationBlocked or
                    err == error.BoundaryElaborationResidualProgramMismatch;
            };
            break :reject false;
        };
        var mask: u8 = 0;
        if (positive_ok) mask |= 0b001;
        if (offered_target_shape.evidenceRef().fingerprint != forged_target_shape.evidenceRef().fingerprint) mask |= 0b010;
        if (forged_rejected) mask |= 0b100;
        break :blk mask;
    };
    try std.testing.expectEqual(@as(u8, 0b111), target_shape_world_port_ok);

    const fresh_world_port = Closure.WorldPort.init(.{
        .label = "stale-elaboration-world-port",
        .kind = .test_fixture,
        .effect_shape_ref = source_shape.evidenceRef(),
        .supported_protocol_labels = &.{"approval"},
        .supported_site_indexes = &.{0},
    });
    var stale_world_port = fresh_world_port;
    stale_world_port.supported_site_indexes = &.{1};
    try std.testing.expect(stale_world_port.fingerprint != stale_world_port.computeFingerprint());
    const stale_world_port_report = Closure.Report.init(.{
        .graph_fingerprint = graph.fingerprint,
        .root_program_refs = &.{source_ref},
        .world_port_refs = &.{fresh_world_port.evidenceRef()},
        .open_world_port_count = 1,
    });
    const stale_world_port_certificate = Closure.Certificate.init(stale_world_port_report, graph, Closure.Policy.auditOnly(), &.{});
    const stale_world_port_input = Elaboration.Input{
        .closure_graph = graph,
        .closure_report = stale_world_port_report,
        .closure_certificate = stale_world_port_certificate,
        .source_program_ref = source_ref,
        .world_ports = &.{stale_world_port},
        .policy = policy,
    };
    try std.testing.expectEqual(error.BoundaryElaborationWorldPortRefMismatch, stale_world_port_input.validate());
}

test "boundary elaboration residual validation rejects uncovered effects and disabled provider linking" {
    @setEvalBranchQuota(3_000_000);
    const Closure = Program.BoundaryClosure;
    const Elaboration = Closure.Elaboration;
    const source_ref = comptime Evidence.refFor(Evidence.domains.program_plan, Program.compiled_plan.hash(), .{ .label = Program.contract.label });
    const provider_ref = Evidence.refFor(Evidence.domains.program_plan, 0xE1D202, .{ .label = "provider" });
    const graph = Closure.Graph.init("residual-validation-graph", &.{}, &.{}, &.{});
    const report = Closure.Report.init(.{
        .graph_fingerprint = graph.fingerprint,
        .root_program_refs = &.{source_ref},
        .provider_program_refs = &.{provider_ref},
    });
    const certificate = Closure.Certificate.init(report, graph, Closure.Policy.auditOnly(), &.{});
    const provider_programs = [_]Closure.ProviderProgram{.{
        .provider_ref = provider_ref,
        .program_ref = provider_ref,
        .effect_free = true,
    }};
    var no_link_policy = Elaboration.Policy.auditOnly();
    no_link_policy.allow_provider_program_linking = false;
    const no_link_input = Elaboration.Input{
        .closure_graph = graph,
        .closure_report = report,
        .closure_certificate = certificate,
        .source_program_ref = source_ref,
        .provider_programs = provider_programs[0..],
        .policy = no_link_policy,
    };
    try std.testing.expectEqual(error.BoundaryElaborationBlocked, no_link_input.validate());

    const uncovered_rejected = comptime blk: {
        @setEvalBranchQuota(20_000);
        const residual_graph = Closure.Graph.init("uncovered-residual-graph", &.{}, &.{}, &.{});
        const residual_source_ref = source_ref;
        const residual_report = Closure.Report.init(.{
            .graph_fingerprint = residual_graph.fingerprint,
            .root_program_refs = &.{residual_source_ref},
        });
        const residual_certificate = Closure.Certificate.init(residual_report, residual_graph, Closure.Policy.auditOnly(), &.{});
        const residual_input = Elaboration.Input{
            .closure_graph = residual_graph,
            .closure_report = residual_report,
            .closure_certificate = residual_certificate,
            .source_program_ref = residual_source_ref,
            .policy = Elaboration.Policy.auditOnly(),
        };
        residual_input.validateResidualProgram(closure_source_program) catch |err| break :blk err == error.BoundaryElaborationResidualProgramMismatch;
        break :blk false;
    };
    try std.testing.expect(uncovered_rejected);

    const from_residual_compiles = comptime blk: {
        @setEvalBranchQuota(200_000);
        const residual_graph = Closure.Graph.init("from-residual-graph", &.{}, &.{}, &.{});
        const residual_source_ref = source_ref;
        const residual_report = Closure.Report.init(.{
            .graph_fingerprint = residual_graph.fingerprint,
            .root_program_refs = &.{residual_source_ref},
        });
        const residual_certificate = Closure.Certificate.init(residual_report, residual_graph, Closure.Policy.auditOnly(), &.{});
        const residual_input = Elaboration.Input{
            .closure_graph = residual_graph,
            .closure_report = residual_report,
            .closure_certificate = residual_certificate,
            .source_program_ref = residual_source_ref,
            .policy = Elaboration.Policy.auditOnly(),
        };
        const Body = Elaboration.FromResidual(residual_input, Program, .{ .label = "from-residual-body" });
        break :blk Body.certificate.evidenceView().domain == Evidence.domains.boundary_elaboration_certificate.id;
    };
    try std.testing.expect(from_residual_compiles);

    const target_from_residual_compiles = comptime blk: {
        @setEvalBranchQuota(300_000);
        const residual_graph = Closure.Graph.init("target-from-residual-graph", &.{}, &.{}, &.{});
        const residual_report = Closure.Report.init(.{
            .graph_fingerprint = residual_graph.fingerprint,
            .root_program_refs = &.{source_ref},
        });
        const residual_certificate = Closure.Certificate.init(residual_report, residual_graph, Closure.Policy.auditOnly(), &.{});
        const residual_input = Elaboration.Input{
            .closure_graph = residual_graph,
            .closure_report = residual_report,
            .closure_certificate = residual_certificate,
            .source_program_ref = source_ref,
            .policy = Elaboration.Policy.auditOnly(),
        };
        const Target = Elaboration.Target.compileComptime(.{
            .label = "target-from-residual-body",
            .input = residual_input,
            .residual_program = Program,
            .policy = Elaboration.Target.Policy.auditOnly(),
        });
        Target.assertWorldSurfaceReady();
        Target.assertNoSearchHotPath();
        break :blk Target.certificate.evidenceView().domain == Evidence.domains.boundary_target_certificate.id and
            Target.normalization_trace.evidenceRef().domain_id == Evidence.domains.boundary_normalization_trace.id and
            Target.normalization_certificate.evidenceView().domain == Evidence.domains.boundary_normalization_certificate.id and
            Target.Certificate.normalization_certificate_ref.?.eql(Target.normalization_certificate.evidenceRef()) and
            Target.NormalizationTrace.rewrite_steps.len == 0 and
            Target.world_surface.evidenceRef().domain_id == Evidence.domains.boundary_world_surface.id and
            Target.world_port_table.entries.len == 0 and
            Target.world_dispatch_table.entries.len == 0;
    };
    try std.testing.expect(target_from_residual_compiles);

    const target_world_policy_ok = comptime blk: {
        @setEvalBranchQuota(300_000);
        const world_nodes = [_]Closure.Graph.Node{.{
            .kind = .root_program,
            .ref = source_ref,
            .label = "target-world-boundary-policy-root",
        }};
        const world_graph = Closure.Graph.init("target-world-boundary-policy-graph", world_nodes[0..], &.{}, &.{});
        const target_policy = Elaboration.Target.Policy.worldBoundary();
        const target_elaboration_policy = target_policy.toElaborationPolicy();
        const closure_policy = target_elaboration_policy.closure_policy;
        const world_report = Closure.Report.init(.{
            .graph_fingerprint = world_graph.fingerprint,
            .policy_summary = closure_policy.policySummary(),
            .root_program_refs = &.{source_ref},
            .effect_free_root_refs = &.{source_ref},
        });
        const world_certificate = Closure.Certificate.init(world_report, world_graph, closure_policy, &.{});
        const world_input = Elaboration.Input{
            .closure_graph = world_graph,
            .closure_report = world_report,
            .closure_certificate = world_certificate,
            .source_program_ref = source_ref,
            .policy = target_elaboration_policy,
        };
        const Target = Elaboration.Target.compileComptime(.{
            .label = "target-world-boundary-policy-body",
            .input = world_input,
            .residual_program = Program,
            .policy = target_policy,
        });
        Target.assertWorldSurfaceReady();
        Target.assertNoSearchHotPath();
        break :blk Target.Body.certificate.evidenceView().domain == Evidence.domains.boundary_elaboration_certificate.id and
            Target.certificate.evidenceView().domain == Evidence.domains.boundary_target_certificate.id;
    };
    try std.testing.expect(target_world_policy_ok);

    const target_policy_unlocks_blockers = comptime blk: {
        @setEvalBranchQuota(300_000);
        const blocker_graph = Closure.Graph.init("target-policy-blocker-graph", &.{}, &.{}, &.{});
        const blocker_source_ref = source_ref;
        const blocked_shape_ref = Evidence.refFor(Evidence.domains.boundary_effect_shape, 0xE1D2_7700, .{ .label = "target.blocked.approval", .site_index = 0 });
        const closure_blocker = Evidence.boundaryClosureBlocker(.{
            .tag = .unsupported_shape_planning,
            .subject = blocked_shape_ref,
            .site_index = 0,
            .summary = "target policy allows partial blocker artifact",
        });
        const blocker_report = Closure.Report.init(.{
            .graph_fingerprint = blocker_graph.fingerprint,
            .root_program_refs = &.{blocker_source_ref},
            .effect_shape_count = 1,
            .blockers = &.{closure_blocker},
        });
        const blocker_certificate = Closure.Certificate.init(blocker_report, blocker_graph, Closure.Policy.auditOnly(), &.{});
        var restrictive_elaboration_policy = Elaboration.Policy.auditOnly();
        restrictive_elaboration_policy.allow_partial_with_blockers = false;
        restrictive_elaboration_policy.fail_on_unsupported_shape = true;
        restrictive_elaboration_policy.max_blockers = 0;
        const blocker_input = Elaboration.Input{
            .closure_graph = blocker_graph,
            .closure_report = blocker_report,
            .closure_certificate = blocker_certificate,
            .source_program_ref = blocker_source_ref,
            .policy = restrictive_elaboration_policy,
        };
        var target_policy = Elaboration.Target.Policy.strictClosed();
        target_policy.elaboration_policy = restrictive_elaboration_policy;
        target_policy.require_checked_closure_certificate = false;
        target_policy.fail_on_unsupported_instruction = false;
        const Target = Elaboration.Target.compileComptime(.{
            .label = "target-policy-blocker-body",
            .input = blocker_input,
            .residual_program = Program,
            .policy = target_policy,
        });
        Target.assertNormalForm(.partial_with_blockers);
        break :blk Target.Certificate.evidenceView().domain == Evidence.domains.boundary_target_certificate.id and
            Target.Body.effect_row.blockers == 1 and
            Target.Redexes.len == 1 and
            Target.NormalizationTrace.eliminated_redex_refs.len == 0 and
            Target.NormalizationTrace.unsupported_redex_refs.len == 1;
    };
    try std.testing.expect(target_policy_unlocks_blockers);

    const target_root_copy = comptime blk: {
        @setEvalBranchQuota(300_000);
        const residual_graph = Closure.Graph.init("target-root-copy-graph", &.{}, &.{}, &.{});
        const residual_report = Closure.Report.init(.{
            .graph_fingerprint = residual_graph.fingerprint,
            .root_program_refs = &.{source_ref},
        });
        const residual_certificate = Closure.Certificate.init(residual_report, residual_graph, Closure.Policy.auditOnly(), &.{});
        const residual_input = Elaboration.Input{
            .closure_graph = residual_graph,
            .closure_report = residual_report,
            .closure_certificate = residual_certificate,
            .source_program_ref = source_ref,
            .policy = Elaboration.Policy.auditOnly(),
        };
        const Target = Elaboration.Target.compileComptime(.{
            .label = "target-root-copy-body",
            .input = residual_input,
            .residual_program = Program,
            .policy = Elaboration.Target.Policy.auditOnly(),
        });
        Target.assertWorldSurfaceReady();
        break :blk Target.Program == Program and
            Target.certificate.residual_program_ref.eql(Elaboration.Target.PlanBuilder.residualProgramRef(residual_input, Program)) and
            Elaboration.Target.PlanBuilder.generatedPlanRef(residual_input, Program).domain_id == Evidence.domains.boundary_elaboration_generated_plan.id;
    };
    try std.testing.expect(target_root_copy);

    const from_residual_nested_targets = comptime blk: {
        @setEvalBranchQuota(200_000);
        const residual_graph = Closure.Graph.init("from-residual-nested-target-graph", &.{}, &.{}, &.{});
        const residual_report = Closure.Report.init(.{
            .graph_fingerprint = residual_graph.fingerprint,
            .root_program_refs = &.{source_ref},
        });
        const residual_certificate = Closure.Certificate.init(residual_report, residual_graph, Closure.Policy.auditOnly(), &.{});
        const residual_input = Elaboration.Input{
            .closure_graph = residual_graph,
            .closure_report = residual_report,
            .closure_certificate = residual_certificate,
            .source_program_ref = source_ref,
            .policy = Elaboration.Policy.auditOnly(),
        };
        const Body = Elaboration.FromResidual(residual_input, nested_unit_program, .{ .label = "from-residual-nested-target-body" });
        const Wrapped = boundary.program("from-residual-nested-target", struct {}, Body);
        break :blk Body.nested_with_targets.len == 1 and
            Wrapped.contract.has_nested_with_targets and
            Wrapped.contract.nested_with_targets.len == 1 and
            std.mem.eql(u8, Wrapped.contract.nested_with_targets[0].metadata, "unit-target") and
            Wrapped.contract.nested_with_targets[0].function_index == 0;
    };
    try std.testing.expect(from_residual_nested_targets);

    const no_trace_evidence = comptime blk: {
        @setEvalBranchQuota(200_000);
        const residual_graph = Closure.Graph.init("from-residual-no-trace-graph", &.{}, &.{}, &.{});
        const residual_report = Closure.Report.init(.{
            .graph_fingerprint = residual_graph.fingerprint,
            .root_program_refs = &.{source_ref},
        });
        const residual_certificate = Closure.Certificate.init(residual_report, residual_graph, Closure.Policy.auditOnly(), &.{});
        var trace_disabled_policy = Elaboration.Policy.auditOnly();
        trace_disabled_policy.emit_trace_map = false;
        const residual_input = Elaboration.Input{
            .closure_graph = residual_graph,
            .closure_report = residual_report,
            .closure_certificate = residual_certificate,
            .source_program_ref = source_ref,
            .policy = trace_disabled_policy,
        };
        const Body = Elaboration.FromResidual(residual_input, Program, .{ .label = "from-residual-no-trace-body" });
        var has_trace_dependency = false;
        for (Body.certificate.dependencies) |dependency| {
            if (dependency.role == .elaboration_trace_map) has_trace_dependency = true;
        }
        break :blk Body.trace_map == null and
            Body.certificate.trace_map_ref == null and
            !has_trace_dependency;
    };
    try std.testing.expect(no_trace_evidence);

    const override_rejected = comptime blk: {
        @setEvalBranchQuota(200_000);
        const override_hash: u64 = 0xE1D2_7701;
        const residual_graph = Closure.Graph.init("from-residual-override-graph", &.{}, &.{}, &.{});
        const residual_report = Closure.Report.init(.{
            .graph_fingerprint = residual_graph.fingerprint,
            .root_program_refs = &.{source_ref},
        });
        const residual_certificate = Closure.Certificate.init(residual_report, residual_graph, Closure.Policy.auditOnly(), &.{});
        const residual_input = Elaboration.Input{
            .closure_graph = residual_graph,
            .closure_report = residual_report,
            .closure_certificate = residual_certificate,
            .source_program_ref = source_ref,
            .policy = Elaboration.Policy.auditOnly(),
            .ir_hash_override = override_hash,
        };
        residual_input.validateResidualProgram(Program) catch |err|
            break :blk err == error.BoundaryElaborationResidualProgramMismatch;
        break :blk false;
    };
    try std.testing.expect(override_rejected);

    const forged_residual_rejected = comptime blk: {
        @setEvalBranchQuota(200_000);
        const forged_graph = Closure.Graph.init("forged-residual-binding-graph", &.{}, &.{}, &.{});
        const forged_provider_ref = Evidence.refFor(Evidence.domains.provider_manifest, 0xE1D212, .{ .label = "forged-residual-provider" });
        const forged_provider_program_ref = Evidence.refFor(Evidence.domains.program_plan, 0xE1D213, .{ .label = "forged-residual-provider-program" });
        const forged_shape = Closure.EffectShape.init(.{
            .program_label = "forged-residual-source",
            .kind = .operation,
            .site_index = 0,
            .protocol_label = "approval",
            .expected_resume_ref = Evidence.BoundaryValueRef.init("unit", null),
        });
        const wrong_residual_ref = Evidence.refFor(Evidence.domains.program_plan, 0xE1D214, .{ .label = "wrong-residual-program" });
        const forged_dependencies = [_]Evidence.Dependency{.{
            .role = .residual_program,
            .ref = wrong_residual_ref,
        }};
        const forged_plan = Closure.StaticTreatyPlan.init(.{
            .label = "forged-residual-plan",
            .source_shape = forged_shape,
            .selected_provider_ref = forged_provider_ref,
            .selected_provider_offer_ref = forged_provider_ref,
            .selected_capability_ref = forged_provider_ref,
            .selected_semantic_body = .boundary_program,
            .selected_provider_program_ref = forged_provider_program_ref,
            .selected_provider_program_mapping_fingerprint = 0xE1D2_1401,
            .selected_provider_program_request_mapping_tag = "payload_to_args",
            .selected_provider_program_result_mapping_tag = "result_to_resume",
            .selected_provider_program_effect_shape_count = 0,
            .selected_provider_program_effect_shape_fingerprint = Evidence.fingerprintBoundaryEffectShapeSet(&.{}),
            .dependencies = forged_dependencies[0..],
        });
        const forged_report = Closure.Report.init(.{
            .graph_fingerprint = forged_graph.fingerprint,
            .root_program_refs = &.{source_ref},
            .provider_program_refs = &.{forged_provider_program_ref},
            .effect_shape_count = 1,
            .closed_effect_shape_count = 1,
        });
        const forged_certificate = Closure.Certificate.init(forged_report, forged_graph, Closure.Policy.auditOnly(), &.{forged_plan.evidenceRef()});
        const forged_provider_programs = [_]Closure.ProviderProgram{.{
            .provider_ref = forged_provider_ref,
            .program_ref = forged_provider_program_ref,
            .provider_program_mapping_fingerprint = forged_plan.selected_provider_program_mapping_fingerprint,
            .provider_program_mapping_support_fingerprint = Closure.providerProgramMappingSupportFingerprintForPlan(forged_plan, .payload_to_args, .result_to_resume),
            .request_mapping = .payload_to_args,
            .result_mapping = .result_to_resume,
            .effect_free = true,
        }};
        const forged_input = Elaboration.Input{
            .closure_graph = forged_graph,
            .closure_report = forged_report,
            .closure_certificate = forged_certificate,
            .static_treaty_plans = &.{forged_plan},
            .source_program_ref = source_ref,
            .provider_programs = forged_provider_programs[0..],
            .policy = Elaboration.Policy.auditOnly(),
        };
        forged_input.validateResidualProgram(Program) catch |err| break :blk err == error.BoundaryElaborationResidualProgramMismatch;
        break :blk false;
    };
    try std.testing.expect(forged_residual_rejected);

    const provider_without_future_dep_ok = comptime blk: {
        @setEvalBranchQuota(200_000);
        const unbound_residual_hash: u64 = 0xE1D2_1502;
        const unbound_residual_ref = Evidence.refFor(Evidence.domains.program_plan, unbound_residual_hash, .{ .label = Program.contract.label });
        const unbound_graph = Closure.Graph.init("provider-without-future-residual-dep-graph", &.{}, &.{}, &.{});
        const unbound_provider_ref = Evidence.refFor(Evidence.domains.provider_manifest, 0xE1D215, .{ .label = "provider-without-future-residual-dep" });
        const unbound_provider_program_ref = Evidence.refFor(Evidence.domains.program_plan, 0xE1D216, .{ .label = "provider-without-future-residual-program" });
        const unbound_shape = Closure.EffectShape.init(.{
            .program_label = "provider-without-future-residual-dep-source",
            .kind = .operation,
            .site_index = 0,
            .protocol_label = "approval",
            .expected_resume_ref = Evidence.BoundaryValueRef.init("unit", null),
        });
        const unbound_plan = Closure.StaticTreatyPlan.init(.{
            .label = "provider-without-future-residual-dep-plan",
            .source_shape = unbound_shape,
            .selected_provider_ref = unbound_provider_ref,
            .selected_provider_offer_ref = unbound_provider_ref,
            .selected_capability_ref = unbound_provider_ref,
            .selected_semantic_body = .boundary_program,
            .selected_provider_program_ref = unbound_provider_program_ref,
            .selected_provider_program_mapping_fingerprint = 0xE1D2_1501,
            .selected_provider_program_request_mapping_tag = "payload_to_args",
            .selected_provider_program_result_mapping_tag = "result_to_resume",
            .selected_provider_program_effect_shape_count = 0,
            .selected_provider_program_effect_shape_fingerprint = Evidence.fingerprintBoundaryEffectShapeSet(&.{}),
        });
        const unbound_report = Closure.Report.init(.{
            .graph_fingerprint = unbound_graph.fingerprint,
            .root_program_refs = &.{source_ref},
            .provider_program_refs = &.{unbound_provider_program_ref},
            .effect_shape_count = 1,
            .closed_effect_shape_count = 1,
        });
        const unbound_certificate = Closure.Certificate.init(unbound_report, unbound_graph, Closure.Policy.auditOnly(), &.{unbound_plan.evidenceRef()});
        const unbound_provider_programs = [_]Closure.ProviderProgram{.{
            .provider_ref = unbound_provider_ref,
            .program_ref = unbound_provider_program_ref,
            .provider_program_mapping_fingerprint = unbound_plan.selected_provider_program_mapping_fingerprint,
            .provider_program_mapping_support_fingerprint = Closure.providerProgramMappingSupportFingerprintForPlan(unbound_plan, .payload_to_args, .result_to_resume),
            .request_mapping = .payload_to_args,
            .result_mapping = .result_to_resume,
            .effect_free = true,
        }};
        const unbound_provider_links = [_]Elaboration.ProviderProgramLink{.{
            .provider_ref = unbound_provider_ref,
            .program_ref = unbound_provider_program_ref,
            .residual_program_ref = unbound_residual_ref,
            .mapping_fingerprint = unbound_plan.selected_provider_program_mapping_fingerprint,
            .mapping_support_fingerprint = unbound_plan.selected_provider_program_mapping_support_fingerprint,
            .effect_shape_ref = unbound_shape.evidenceRef(),
        }};
        const underspecified_provider_links = [_]Elaboration.ProviderProgramLink{.{
            .provider_ref = unbound_provider_ref,
            .program_ref = unbound_provider_program_ref,
            .residual_program_ref = unbound_residual_ref,
        }};
        const forged_support_provider_links = [_]Elaboration.ProviderProgramLink{.{
            .provider_ref = unbound_provider_ref,
            .program_ref = unbound_provider_program_ref,
            .residual_program_ref = unbound_residual_ref,
            .mapping_fingerprint = unbound_plan.selected_provider_program_mapping_fingerprint,
            .mapping_support_fingerprint = unbound_plan.selected_provider_program_mapping_support_fingerprint.? +% 1,
            .effect_shape_ref = unbound_shape.evidenceRef(),
        }};
        const underspecified_input = Elaboration.Input{
            .closure_graph = unbound_graph,
            .closure_report = unbound_report,
            .closure_certificate = unbound_certificate,
            .static_treaty_plans = &.{unbound_plan},
            .source_program_ref = source_ref,
            .provider_programs = unbound_provider_programs[0..],
            .provider_program_links = underspecified_provider_links[0..],
            .policy = Elaboration.Policy.auditOnly(),
            .ir_hash_override = unbound_residual_hash,
        };
        const underspecified_rejected = if (underspecified_input.validateResidualProgram(Program)) |_| false else |err| err == error.BoundaryElaborationResidualProgramMismatch;
        if (!underspecified_rejected) break :blk false;
        var forged_support_input = underspecified_input;
        forged_support_input.provider_program_links = forged_support_provider_links[0..];
        const forged_support_rejected = if (forged_support_input.validateResidualProgram(Program)) |_| false else |err| err == error.BoundaryElaborationResidualProgramMismatch;
        if (!forged_support_rejected) break :blk false;
        const unbound_input = Elaboration.Input{
            .closure_graph = unbound_graph,
            .closure_report = unbound_report,
            .closure_certificate = unbound_certificate,
            .static_treaty_plans = &.{unbound_plan},
            .source_program_ref = source_ref,
            .provider_programs = unbound_provider_programs[0..],
            .provider_program_links = unbound_provider_links[0..],
            .policy = Elaboration.Policy.auditOnly(),
            .ir_hash_override = unbound_residual_hash,
        };
        unbound_input.validateResidualProgram(Program) catch |err|
            break :blk err == error.BoundaryElaborationResidualProgramMismatch;
        break :blk false;
    };
    try std.testing.expect(provider_without_future_dep_ok);

    const provider_rebind_rejected = comptime blk: {
        @setEvalBranchQuota(200_000);
        const rebind_graph = Closure.Graph.init("provider-without-dep-rebind-graph", &.{}, &.{}, &.{});
        const rebind_provider_ref = Evidence.refFor(Evidence.domains.provider_manifest, 0xE1D238, .{ .label = "provider-without-dep-rebind" });
        const rebind_program_ref = Evidence.refFor(Evidence.domains.program_plan, 0xE1D239, .{ .label = "provider-without-dep-rebind-program" });
        const rebind_shape = Closure.EffectShape.init(.{
            .program_label = "provider-without-dep-rebind-source",
            .kind = .operation,
            .site_index = 0,
            .protocol_label = "approval",
            .expected_resume_ref = Evidence.BoundaryValueRef.init("unit", null),
        });
        const rebind_plan = Closure.StaticTreatyPlan.init(.{
            .label = "provider-without-dep-rebind-plan",
            .source_shape = rebind_shape,
            .selected_provider_ref = rebind_provider_ref,
            .selected_provider_offer_ref = rebind_provider_ref,
            .selected_capability_ref = rebind_provider_ref,
            .selected_semantic_body = .boundary_program,
            .selected_provider_program_ref = rebind_program_ref,
            .selected_provider_program_mapping_fingerprint = 0xE1D2_3901,
            .selected_provider_program_request_mapping_tag = "payload_to_args",
            .selected_provider_program_result_mapping_tag = "result_to_resume",
            .selected_provider_program_effect_shape_count = 0,
            .selected_provider_program_effect_shape_fingerprint = Evidence.fingerprintBoundaryEffectShapeSet(&.{}),
        });
        const rebind_report = Closure.Report.init(.{
            .graph_fingerprint = rebind_graph.fingerprint,
            .root_program_refs = &.{source_ref},
            .provider_program_refs = &.{rebind_program_ref},
            .effect_shape_count = 1,
            .closed_effect_shape_count = 1,
        });
        const rebind_certificate = Closure.Certificate.init(rebind_report, rebind_graph, Closure.Policy.auditOnly(), &.{rebind_plan.evidenceRef()});
        const rebind_programs = [_]Closure.ProviderProgram{.{
            .provider_ref = rebind_provider_ref,
            .program_ref = rebind_program_ref,
            .provider_program_mapping_fingerprint = rebind_plan.selected_provider_program_mapping_fingerprint,
            .provider_program_mapping_support_fingerprint = Closure.providerProgramMappingSupportFingerprintForPlan(rebind_plan, .payload_to_args, .result_to_resume),
            .request_mapping = .payload_to_args,
            .result_mapping = .result_to_resume,
            .effect_free = true,
        }};
        const rebind_input = Elaboration.Input{
            .closure_graph = rebind_graph,
            .closure_report = rebind_report,
            .closure_certificate = rebind_certificate,
            .static_treaty_plans = &.{rebind_plan},
            .source_program_ref = source_ref,
            .provider_programs = rebind_programs[0..],
            .policy = Elaboration.Policy.auditOnly(),
        };
        rebind_input.validateResidualProgram(closure_source_program) catch |err|
            break :blk err == error.BoundaryElaborationResidualProgramMismatch;
        break :blk false;
    };
    try std.testing.expect(provider_rebind_rejected);

    const unsupported_mapping_rejected = comptime blk: {
        @setEvalBranchQuota(200_000);
        const unsupported_graph = Closure.Graph.init("unsupported-provider-mapping-graph", &.{}, &.{}, &.{});
        const unsupported_provider_ref = Evidence.refFor(Evidence.domains.provider_manifest, 0xE1D240, .{ .label = "unsupported-provider-mapping-provider" });
        const unsupported_program_ref = Evidence.refFor(Evidence.domains.program_plan, 0xE1D241, .{ .label = "unsupported-provider-mapping-program" });
        const unsupported_shape = Closure.EffectShape.init(.{
            .program_label = "unsupported-provider-mapping-source",
            .kind = .operation,
            .site_index = 0,
            .protocol_label = "approval",
            .expected_resume_ref = Evidence.BoundaryValueRef.init("unit", null),
        });
        const unsupported_plan = Closure.StaticTreatyPlan.init(.{
            .label = "unsupported-provider-mapping-plan",
            .source_shape = unsupported_shape,
            .selected_provider_ref = unsupported_provider_ref,
            .selected_provider_offer_ref = unsupported_provider_ref,
            .selected_capability_ref = unsupported_provider_ref,
            .selected_semantic_body = .boundary_program,
            .selected_provider_program_ref = unsupported_program_ref,
            .selected_provider_program_mapping_fingerprint = 0xE1D2_4001,
            .selected_provider_program_request_mapping_tag = "payload_to_args",
            .selected_provider_program_result_mapping_tag = "result_to_resume",
            .selected_provider_program_effect_shape_count = 0,
            .selected_provider_program_effect_shape_fingerprint = Evidence.fingerprintBoundaryEffectShapeSet(&.{}),
        });
        const unsupported_report = Closure.Report.init(.{
            .graph_fingerprint = unsupported_graph.fingerprint,
            .root_program_refs = &.{source_ref},
            .provider_program_refs = &.{unsupported_program_ref},
            .effect_shape_count = 1,
            .closed_effect_shape_count = 1,
        });
        const unsupported_certificate = Closure.Certificate.init(unsupported_report, unsupported_graph, Closure.Policy.auditOnly(), &.{unsupported_plan.evidenceRef()});
        const unsupported_programs = [_]Closure.ProviderProgram{.{
            .provider_ref = unsupported_provider_ref,
            .program_ref = unsupported_program_ref,
            .provider_program_mapping_fingerprint = unsupported_plan.selected_provider_program_mapping_fingerprint,
            .provider_program_mapping_support_fingerprint = Closure.providerProgramMappingSupportFingerprintForPlan(unsupported_plan, .payload_to_args, .result_to_outcome_union),
            .request_mapping = .payload_to_args,
            .result_mapping = .result_to_outcome_union,
            .effect_free = true,
        }};
        const unsupported_input = Elaboration.Input{
            .closure_graph = unsupported_graph,
            .closure_report = unsupported_report,
            .closure_certificate = unsupported_certificate,
            .static_treaty_plans = &.{unsupported_plan},
            .source_program_ref = source_ref,
            .provider_programs = unsupported_programs[0..],
            .policy = Elaboration.Policy.auditOnly(),
        };
        const unsupported_rejected = reject: {
            unsupported_input.validate() catch |err| break :reject err == error.BoundaryElaborationProviderProgramRefMismatch;
            break :reject false;
        };
        const non_unit_shape = Closure.EffectShape.init(.{
            .program_label = "unsupported-provider-mapping-source",
            .kind = .operation,
            .site_index = 0,
            .protocol_label = "approval",
            .value_ref = Evidence.BoundaryValueRef.init("product", 1),
        });
        const unit_args_plan = Closure.StaticTreatyPlan.init(.{
            .label = "unsupported-provider-unit-args-plan",
            .source_shape = non_unit_shape,
            .selected_provider_ref = unsupported_provider_ref,
            .selected_provider_offer_ref = unsupported_provider_ref,
            .selected_capability_ref = unsupported_provider_ref,
            .selected_semantic_body = .boundary_program,
            .selected_provider_program_ref = unsupported_program_ref,
            .selected_provider_program_mapping_fingerprint = 0xE1D2_4002,
            .selected_provider_program_request_mapping_tag = "unit_args",
            .selected_provider_program_result_mapping_tag = "result_to_resume",
            .selected_provider_program_effect_shape_count = 0,
            .selected_provider_program_effect_shape_fingerprint = Evidence.fingerprintBoundaryEffectShapeSet(&.{}),
        });
        const unit_args_certificate = Closure.Certificate.init(unsupported_report, unsupported_graph, Closure.Policy.auditOnly(), &.{unit_args_plan.evidenceRef()});
        const unit_args_programs = [_]Closure.ProviderProgram{.{
            .provider_ref = unsupported_provider_ref,
            .program_ref = unsupported_program_ref,
            .provider_program_mapping_fingerprint = unit_args_plan.selected_provider_program_mapping_fingerprint,
            .provider_program_mapping_support_fingerprint = Closure.providerProgramMappingSupportFingerprintForPlan(unit_args_plan, .unit_args, .result_to_resume),
            .request_mapping = .unit_args,
            .result_mapping = .result_to_resume,
            .effect_free = true,
        }};
        const unit_args_input = Elaboration.Input{
            .closure_graph = unsupported_graph,
            .closure_report = unsupported_report,
            .closure_certificate = unit_args_certificate,
            .static_treaty_plans = &.{unit_args_plan},
            .source_program_ref = source_ref,
            .provider_programs = unit_args_programs[0..],
            .policy = Elaboration.Policy.auditOnly(),
        };
        const unit_args_rejected = reject: {
            unit_args_input.validate() catch |err| break :reject err == error.BoundaryElaborationProviderProgramRefMismatch;
            break :reject false;
        };
        const unknown_value_shape = Closure.EffectShape.init(.{
            .program_label = "unsupported-provider-mapping-source",
            .kind = .operation,
            .site_index = 0,
            .protocol_label = "approval",
        });
        const unknown_value_unit_args_plan = Closure.StaticTreatyPlan.init(.{
            .label = "unsupported-provider-unknown-value-unit-args-plan",
            .source_shape = unknown_value_shape,
            .selected_provider_ref = unsupported_provider_ref,
            .selected_provider_offer_ref = unsupported_provider_ref,
            .selected_capability_ref = unsupported_provider_ref,
            .selected_semantic_body = .boundary_program,
            .selected_provider_program_ref = unsupported_program_ref,
            .selected_provider_program_mapping_fingerprint = 0xE1D2_4007,
            .selected_provider_program_request_mapping_tag = "unit_args",
            .selected_provider_program_result_mapping_tag = "result_to_resume",
            .selected_provider_program_effect_shape_count = 0,
            .selected_provider_program_effect_shape_fingerprint = Evidence.fingerprintBoundaryEffectShapeSet(&.{}),
        });
        const unknown_value_certificate = Closure.Certificate.init(unsupported_report, unsupported_graph, Closure.Policy.auditOnly(), &.{unknown_value_unit_args_plan.evidenceRef()});
        const unknown_value_programs = [_]Closure.ProviderProgram{.{
            .provider_ref = unsupported_provider_ref,
            .program_ref = unsupported_program_ref,
            .provider_program_mapping_fingerprint = unknown_value_unit_args_plan.selected_provider_program_mapping_fingerprint,
            .provider_program_mapping_support_fingerprint = Closure.providerProgramMappingSupportFingerprintForPlan(unknown_value_unit_args_plan, .unit_args, .result_to_resume),
            .request_mapping = .unit_args,
            .result_mapping = .result_to_resume,
            .effect_free = true,
        }};
        const unknown_value_input = Elaboration.Input{
            .closure_graph = unsupported_graph,
            .closure_report = unsupported_report,
            .closure_certificate = unknown_value_certificate,
            .static_treaty_plans = &.{unknown_value_unit_args_plan},
            .source_program_ref = source_ref,
            .provider_programs = unknown_value_programs[0..],
            .policy = Elaboration.Policy.auditOnly(),
        };
        const unknown_value_rejected = reject: {
            unknown_value_input.validate() catch |err| break :reject err == error.BoundaryElaborationProviderProgramRefMismatch;
            break :reject false;
        };
        const resume_after_plan = Closure.StaticTreatyPlan.init(.{
            .label = "unsupported-provider-resume-after-plan",
            .source_shape = unsupported_shape,
            .selected_provider_ref = unsupported_provider_ref,
            .selected_provider_offer_ref = unsupported_provider_ref,
            .selected_capability_ref = unsupported_provider_ref,
            .selected_semantic_body = .boundary_program,
            .selected_provider_program_ref = unsupported_program_ref,
            .selected_provider_program_mapping_fingerprint = 0xE1D2_4003,
            .selected_provider_program_request_mapping_tag = "payload_to_args",
            .selected_provider_program_result_mapping_tag = "result_to_resume_after",
            .selected_provider_program_effect_shape_count = 0,
            .selected_provider_program_effect_shape_fingerprint = Evidence.fingerprintBoundaryEffectShapeSet(&.{}),
        });
        const resume_after_certificate = Closure.Certificate.init(unsupported_report, unsupported_graph, Closure.Policy.auditOnly(), &.{resume_after_plan.evidenceRef()});
        const resume_after_programs = [_]Closure.ProviderProgram{.{
            .provider_ref = unsupported_provider_ref,
            .program_ref = unsupported_program_ref,
            .provider_program_mapping_fingerprint = resume_after_plan.selected_provider_program_mapping_fingerprint,
            .provider_program_mapping_support_fingerprint = Closure.providerProgramMappingSupportFingerprintForPlan(resume_after_plan, .payload_to_args, .result_to_resume_after),
            .request_mapping = .payload_to_args,
            .result_mapping = .result_to_resume_after,
            .effect_free = true,
        }};
        const resume_after_input = Elaboration.Input{
            .closure_graph = unsupported_graph,
            .closure_report = unsupported_report,
            .closure_certificate = resume_after_certificate,
            .static_treaty_plans = &.{resume_after_plan},
            .source_program_ref = source_ref,
            .provider_programs = resume_after_programs[0..],
            .policy = Elaboration.Policy.auditOnly(),
        };
        const resume_after_rejected = reject: {
            resume_after_input.validate() catch |err| break :reject err == error.BoundaryElaborationProviderProgramRefMismatch;
            break :reject false;
        };
        const forged_supported_programs = [_]Closure.ProviderProgram{.{
            .provider_ref = unsupported_provider_ref,
            .program_ref = unsupported_program_ref,
            .provider_program_mapping_fingerprint = unsupported_plan.selected_provider_program_mapping_fingerprint,
            .provider_program_mapping_support_fingerprint = Closure.providerProgramMappingSupportFingerprintForPlan(unsupported_plan, .payload_to_args, .result_to_outcome_union),
            .request_mapping = .payload_to_args,
            .result_mapping = .result_to_resume,
            .effect_free = true,
        }};
        var forged_supported_input = unsupported_input;
        forged_supported_input.provider_programs = forged_supported_programs[0..];
        const forged_supported_rejected = reject: {
            forged_supported_input.validate() catch |err| break :reject err == error.BoundaryElaborationProviderProgramRefMismatch;
            break :reject false;
        };
        break :blk unsupported_rejected and
            unit_args_rejected and
            unknown_value_rejected and
            resume_after_rejected and
            forged_supported_rejected;
    };
    try std.testing.expect(unsupported_mapping_rejected);

    const provider_residual_compiles = comptime blk: {
        @setEvalBranchQuota(200_000);
        const provider_graph = Closure.Graph.init("from-residual-provider-graph", &.{}, &.{}, &.{});
        const provider_source_ref = source_ref;
        const provider_residual_ref = Evidence.refFor(Evidence.domains.program_plan, Program.compiled_plan.hash(), .{ .label = Program.contract.label });
        const linked_provider_ref = Evidence.refFor(Evidence.domains.provider_manifest, 0xE1D216, .{ .label = "from-residual-provider" });
        const linked_provider_program_ref = Evidence.refFor(Evidence.domains.program_plan, 0xE1D217, .{ .label = "from-residual-provider-program" });
        const provider_shape = Closure.EffectShape.init(.{
            .program_label = "from-residual-provider-source",
            .kind = .operation,
            .site_index = closure_approval_request.index,
            .protocol_label = "approval",
            .protocol_op_fingerprint = closure_approval_request.fingerprint,
            .expected_resume_ref = Evidence.BoundaryValueRef.init("unit", null),
        });
        const first_nested_shape = Closure.EffectShape.init(.{
            .program_label = "from-residual-provider-program",
            .plan_hash = linked_provider_program_ref.fingerprint,
            .kind = .operation,
            .site_index = 0,
            .protocol_label = "nested-first",
        });
        const second_nested_shape = Closure.EffectShape.init(.{
            .program_label = "from-residual-provider-program",
            .plan_hash = linked_provider_program_ref.fingerprint,
            .kind = .operation,
            .site_index = 1,
            .protocol_label = "nested-second",
        });
        const unselected_nested_shape = Closure.EffectShape.init(.{
            .program_label = "from-residual-provider-program",
            .plan_hash = linked_provider_program_ref.fingerprint,
            .kind = .operation,
            .site_index = 2,
            .protocol_label = "unselected-nested",
        });
        const provider_plan = Closure.StaticTreatyPlan.init(.{
            .label = "from-residual-provider-plan",
            .source_shape = provider_shape,
            .selected_provider_ref = linked_provider_ref,
            .selected_provider_offer_ref = linked_provider_ref,
            .selected_capability_ref = linked_provider_ref,
            .selected_semantic_body = .boundary_program,
            .selected_provider_program_ref = linked_provider_program_ref,
            .selected_provider_program_mapping_fingerprint = 0xE1D2_1701,
            .selected_provider_program_request_mapping_tag = "payload_to_args",
            .selected_provider_program_result_mapping_tag = "result_to_resume",
            .selected_provider_program_effect_shape_count = 2,
            .selected_provider_program_effect_shape_fingerprint = Evidence.fingerprintBoundaryEffectShapeSet(&.{ first_nested_shape, second_nested_shape }),
        });
        const provider_report = Closure.Report.init(.{
            .graph_fingerprint = provider_graph.fingerprint,
            .root_program_refs = &.{provider_source_ref},
            .provider_program_refs = &.{linked_provider_program_ref},
            .effect_shape_count = 1,
            .closed_effect_shape_count = 1,
        });
        const provider_certificate = Closure.Certificate.init(provider_report, provider_graph, Closure.Policy.auditOnly(), &.{provider_plan.evidenceRef()});
        const linked_provider_programs = [_]Closure.ProviderProgram{ .{
            .provider_ref = linked_provider_ref,
            .program_ref = linked_provider_program_ref,
            .provider_program_mapping_fingerprint = provider_plan.selected_provider_program_mapping_fingerprint,
            .provider_program_mapping_support_fingerprint = Closure.providerProgramMappingSupportFingerprintForPlan(provider_plan, .payload_to_args, .result_to_resume),
            .request_mapping = .payload_to_args,
            .result_mapping = .result_to_resume,
            .shapes = &.{ first_nested_shape, second_nested_shape },
        }, .{
            .provider_ref = linked_provider_ref,
            .program_ref = linked_provider_program_ref,
            .provider_program_mapping_fingerprint = 0xE1D2_1702,
            .request_mapping = .payload_to_args,
            .result_mapping = .result_to_resume,
            .shapes = &.{unselected_nested_shape},
        } };
        const provider_input = Elaboration.Input{
            .closure_graph = provider_graph,
            .closure_report = provider_report,
            .closure_certificate = provider_certificate,
            .static_treaty_plans = &.{provider_plan},
            .source_program_ref = provider_source_ref,
            .residual_program_ref = provider_residual_ref,
            .provider_programs = linked_provider_programs[0..],
            .policy = Elaboration.Policy.auditOnly(),
        };
        var zero_depth_policy = Elaboration.Policy.auditOnly();
        zero_depth_policy.max_nested_provider_depth = 0;
        var zero_depth_provider_input = provider_input;
        zero_depth_provider_input.policy = zero_depth_policy;
        const zero_depth_rejected = reject: {
            zero_depth_provider_input.validate() catch |err| break :reject err == error.BoundaryElaborationBlocked;
            break :reject false;
        };
        var shallow_depth_policy = Elaboration.Policy.auditOnly();
        shallow_depth_policy.max_nested_provider_depth = 1;
        var shallow_depth_provider_input = provider_input;
        shallow_depth_provider_input.policy = shallow_depth_policy;
        shallow_depth_provider_input.validate() catch break :blk false;
        const Body = Elaboration.FromResidual(provider_input, Program, .{ .label = "from-residual-provider-body" });
        break :blk zero_depth_rejected and
            Body.source_map.entries.len == 1 and
            Body.source_map.entries[0].disposition == .provider_program_linked and
            Body.effect_row.provider_program_links == 1 and
            Body.effect_row.nested_provider_shapes_linked == 2 and
            Body.effect_row.nested_provider_depth == 1 and
            Body.certificate.summary_counts.nested_provider_shapes_linked == 2 and
            Body.certificate.summary_counts.nested_provider_depth == 1 and
            Body.certificate.inlined_provider_program_refs.len == 1;
    };
    try std.testing.expect(provider_residual_compiles);

    const shared_provider_routes = comptime blk: {
        @setEvalBranchQuota(200_000);
        const provider_graph = Closure.Graph.init("from-residual-shared-provider-graph", &.{}, &.{}, &.{});
        const source_ref_a = source_ref;
        const provider_ref_a = Evidence.refFor(Evidence.domains.provider_manifest, 0xE1D220, .{ .label = "shared-provider" });
        const program_ref_a = Evidence.refFor(Evidence.domains.program_plan, 0xE1D221, .{ .label = "shared-provider-program" });
        const first_shape = Closure.EffectShape.init(.{
            .program_label = "shared-provider-source",
            .kind = .operation,
            .site_index = 0,
            .protocol_label = "approval",
            .expected_resume_ref = Evidence.BoundaryValueRef.init("unit", null),
        });
        const second_shape = Closure.EffectShape.init(.{
            .program_label = "shared-provider-source",
            .kind = .operation,
            .site_index = 1,
            .protocol_label = "approval",
            .expected_resume_ref = Evidence.BoundaryValueRef.init("unit", null),
        });
        const first_plan = Closure.StaticTreatyPlan.init(.{
            .label = "shared-provider-first-plan",
            .source_shape = first_shape,
            .selected_provider_ref = provider_ref_a,
            .selected_provider_offer_ref = provider_ref_a,
            .selected_capability_ref = provider_ref_a,
            .selected_semantic_body = .boundary_program,
            .selected_provider_program_ref = program_ref_a,
            .selected_provider_program_mapping_fingerprint = 0xE1D2_2101,
            .selected_provider_program_request_mapping_tag = "payload_to_args",
            .selected_provider_program_result_mapping_tag = "result_to_resume",
            .selected_provider_program_effect_shape_count = 0,
            .selected_provider_program_effect_shape_fingerprint = Evidence.fingerprintBoundaryEffectShapeSet(&.{}),
        });
        const second_plan = Closure.StaticTreatyPlan.init(.{
            .label = "shared-provider-second-plan",
            .source_shape = second_shape,
            .selected_provider_ref = provider_ref_a,
            .selected_provider_offer_ref = provider_ref_a,
            .selected_capability_ref = provider_ref_a,
            .selected_semantic_body = .boundary_program,
            .selected_provider_program_ref = program_ref_a,
            .selected_provider_program_mapping_fingerprint = 0xE1D2_2101,
            .selected_provider_program_request_mapping_tag = "payload_to_args",
            .selected_provider_program_result_mapping_tag = "result_to_resume",
            .selected_provider_program_effect_shape_count = 0,
            .selected_provider_program_effect_shape_fingerprint = Evidence.fingerprintBoundaryEffectShapeSet(&.{}),
        });
        const provider_report = Closure.Report.init(.{
            .graph_fingerprint = provider_graph.fingerprint,
            .root_program_refs = &.{source_ref_a},
            .provider_program_refs = &.{program_ref_a},
            .effect_shape_count = 2,
            .closed_effect_shape_count = 2,
        });
        const provider_certificate = Closure.Certificate.init(provider_report, provider_graph, Closure.Policy.auditOnly(), &.{ first_plan.evidenceRef(), second_plan.evidenceRef() });
        const linked_programs = [_]Closure.ProviderProgram{.{
            .provider_ref = provider_ref_a,
            .program_ref = program_ref_a,
            .provider_program_mapping_fingerprint = first_plan.selected_provider_program_mapping_fingerprint,
            .provider_program_mapping_support_fingerprint = Closure.providerProgramMappingSupportFingerprintForPlan(first_plan, .payload_to_args, .result_to_resume),
            .request_mapping = .payload_to_args,
            .result_mapping = .result_to_resume,
            .effect_free = true,
        }};
        const provider_input = Elaboration.Input{
            .closure_graph = provider_graph,
            .closure_report = provider_report,
            .closure_certificate = provider_certificate,
            .static_treaty_plans = &.{ first_plan, second_plan },
            .source_program_ref = source_ref_a,
            .residual_program_ref = source_ref_a,
            .provider_programs = linked_programs[0..],
            .policy = Elaboration.Policy.auditOnly(),
        };
        const Body = Elaboration.FromResidual(provider_input, Program, .{ .label = "from-residual-shared-provider-body" });
        break :blk Body.effect_row.provider_program_links == 2 and
            Body.effect_row.linked_provider_programs == 1 and
            Body.certificate.summary_counts.provider_programs_linked == 1;
    };
    try std.testing.expect(shared_provider_routes);

    const residual_blocker_ref_bound = comptime blk: {
        @setEvalBranchQuota(200_000);
        const blocker_graph = Closure.Graph.init("from-residual-blocker-graph", &.{}, &.{}, &.{});
        const blocker_source_ref = source_ref;
        const closure_blocker = Evidence.boundaryClosureBlocker(.{
            .tag = .unsupported_shape_planning,
            .subject = blocker_source_ref,
            .summary = "unsupported elaboration shape",
        });
        const blocker_report = Closure.Report.init(.{
            .graph_fingerprint = blocker_graph.fingerprint,
            .root_program_refs = &.{blocker_source_ref},
            .blockers = &.{closure_blocker},
        });
        const blocker_certificate = Closure.Certificate.init(blocker_report, blocker_graph, Closure.Policy.auditOnly(), &.{});
        const blocker_input = Elaboration.Input{
            .closure_graph = blocker_graph,
            .closure_report = blocker_report,
            .closure_certificate = blocker_certificate,
            .source_program_ref = blocker_source_ref,
            .policy = Elaboration.Policy.auditOnly(),
        };
        const Body = Elaboration.FromResidual(blocker_input, Program, .{ .label = "from-residual-blocker-body" });
        break :blk Body.certificate.blocker_refs.len == 1 and
            Body.certificate.blocker_refs[0].eql(Evidence.refForBoundaryClosureBlocker(closure_blocker)) and
            Body.source_map.entries.len == 1 and
            Body.source_map.entries[0].disposition == .blocked and
            Body.source_map.entries[0].blocker_ref.?.eql(Evidence.refForBoundaryClosureBlocker(closure_blocker));
    };
    try std.testing.expect(residual_blocker_ref_bound);

    const blocker_only_source_map_bound = comptime blk: {
        @setEvalBranchQuota(200_000);
        const blocker_graph = Closure.Graph.init("from-residual-blocker-map-graph", &.{}, &.{}, &.{});
        const blocker_source_ref = source_ref;
        const blocked_shape_ref = Evidence.refFor(Evidence.domains.boundary_effect_shape, 0xE1D219, .{ .label = "blocked.approval", .site_index = 0 });
        const closure_blocker = Evidence.boundaryClosureBlocker(.{
            .tag = .unsupported_shape_planning,
            .subject = blocked_shape_ref,
            .site_index = 0,
            .summary = "blocked shape has no elaborable route",
        });
        const blocker_report = Closure.Report.init(.{
            .graph_fingerprint = blocker_graph.fingerprint,
            .root_program_refs = &.{blocker_source_ref},
            .effect_shape_count = 1,
            .blockers = &.{closure_blocker},
        });
        const blocker_certificate = Closure.Certificate.init(blocker_report, blocker_graph, Closure.Policy.auditOnly(), &.{});
        const blocker_input = Elaboration.Input{
            .closure_graph = blocker_graph,
            .closure_report = blocker_report,
            .closure_certificate = blocker_certificate,
            .source_program_ref = blocker_source_ref,
            .policy = Elaboration.Policy.auditOnly(),
        };
        const Body = Elaboration.FromResidual(blocker_input, Program, .{ .label = "from-residual-blocker-map-body" });
        break :blk Body.normal_form.kind == .partial_with_blockers and
            Body.source_map.entries.len == 1 and
            Body.source_map.entries[0].disposition == .blocked and
            Body.source_map.entries[0].source_ref.eql(blocked_shape_ref) and
            Body.source_map.entries[0].blocker_ref.?.eql(Evidence.refForBoundaryClosureBlocker(closure_blocker)) and
            Body.effect_row.source_effect_shapes == 1;
    };
    try std.testing.expect(blocker_only_source_map_bound);

    const direct_blocker_uses_ref = comptime blk: {
        @setEvalBranchQuota(200_000);
        const blocker_graph = Closure.Graph.init("from-residual-forged-blocker-label-graph", &.{}, &.{}, &.{});
        const blocker_source_ref = source_ref;
        const blocked_shape_ref = Evidence.refFor(Evidence.domains.boundary_effect_shape, 0xE1D21B, .{ .label = "blocked.approval.forged-label", .site_index = 0 });
        const closure_blocker = Evidence.boundaryClosureBlocker(.{
            .tag = .unsupported_shape_planning,
            .subject = blocked_shape_ref,
            .site_index = 0,
            .summary = "blocked shape has no elaborable route",
        });
        const blocker_ref = Evidence.refForBoundaryClosureBlocker(closure_blocker);
        const blocker_report = Closure.Report.init(.{
            .graph_fingerprint = blocker_graph.fingerprint,
            .root_program_refs = &.{blocker_source_ref},
            .effect_shape_count = 1,
            .blockers = &.{closure_blocker},
        });
        const blocker_certificate = Closure.Certificate.init(blocker_report, blocker_graph, Closure.Policy.auditOnly(), &.{});
        var blocker_policy = Elaboration.Policy.auditOnly();
        blocker_policy.emit_trace_map = false;
        blocker_policy.fail_on_unsupported_shape = true;
        blocker_policy.max_blockers = 1;
        const forged_entries = [_]Elaboration.SourceMap.Entry{.{
            .source_ref = blocked_shape_ref,
            .residual_ref = source_ref,
            .source_site_index = 0,
            .blocker_ref = blocker_ref,
            .disposition = .blocked,
            .label = @tagName(Evidence.BoundaryClosureBlockerTag.cycle_detected),
        }};
        const forged_source_map = Elaboration.SourceMap.init("from-residual-forged-blocker-label-source-map", forged_entries[0..], &.{});
        const forged_effect_row = Elaboration.EffectRow.init(.{
            .label = "from-residual-forged-blocker-label-effect-row",
            .source_program_ref = blocker_source_ref,
            .residual_program_ref = source_ref,
            .normal_form = .partial_with_blockers,
            .source_effect_shapes = 1,
            .blockers = 1,
        });
        const forged_normal_form = Elaboration.NormalForm.init(
            "from-residual-forged-blocker-label-normal-form",
            .partial_with_blockers,
            blocker_certificate.evidenceRef(),
            forged_effect_row.evidenceRef(),
            1,
        );
        const forged_certificate = Elaboration.Certificate.init(.{
            .elaborated_program_label = Program.contract.label,
            .source_program_ref = blocker_source_ref,
            .residual_program_ref = source_ref,
            .closure_certificate_ref = blocker_certificate.evidenceRef(),
            .closure_graph_ref = blocker_graph.evidenceRef(),
            .closure_report_ref = blocker_report.evidenceRef(),
            .source_map_ref = forged_source_map.evidenceRef(),
            .effect_row_ref = forged_effect_row.evidenceRef(),
            .normal_form_ref = forged_normal_form.evidenceRef(),
            .policy = blocker_policy,
            .normal_form = .partial_with_blockers,
            .blocker_refs = &.{blocker_ref},
            .summary_counts = .{
                .root_effect_shapes = 1,
                .blockers = 1,
            },
        });
        forged_certificate.check(
            blocker_policy,
            blocker_graph.evidenceRef(),
            blocker_report.evidenceRef(),
            blocker_certificate.evidenceRef(),
            forged_source_map,
            forged_effect_row,
            null,
            forged_normal_form,
            &.{},
            &.{},
        ) catch |err| break :blk err == error.BoundaryElaborationCertificateMismatch or
            err == error.BoundaryElaborationBlocked;
        break :blk false;
    };
    try std.testing.expect(direct_blocker_uses_ref);

    const cycle_blocker_not_shape = comptime blk: {
        @setEvalBranchQuota(200_000);
        const blocker_graph = Closure.Graph.init("from-residual-cycle-blocker-map-graph", &.{}, &.{}, &.{});
        const blocker_source_ref = source_ref;
        const blocked_shape_ref = Evidence.refFor(Evidence.domains.boundary_effect_shape, 0xE1D21A, .{ .label = "blocked.approval.cycle", .site_index = 0 });
        const closure_blocker = Evidence.boundaryClosureBlocker(.{
            .tag = .cycle_detected,
            .subject = blocked_shape_ref,
            .site_index = 0,
            .summary = "provider traversal cycle blocks shape without marking unsupported shape",
        });
        const blocker_report = Closure.Report.init(.{
            .graph_fingerprint = blocker_graph.fingerprint,
            .root_program_refs = &.{blocker_source_ref},
            .effect_shape_count = 1,
            .blockers = &.{closure_blocker},
        });
        const blocker_certificate = Closure.Certificate.init(blocker_report, blocker_graph, Closure.Policy.auditOnly(), &.{});
        var blocker_policy = Elaboration.Policy.auditOnly();
        blocker_policy.fail_on_unsupported_shape = true;
        blocker_policy.max_blockers = 1;
        const blocker_input = Elaboration.Input{
            .closure_graph = blocker_graph,
            .closure_report = blocker_report,
            .closure_certificate = blocker_certificate,
            .source_program_ref = blocker_source_ref,
            .policy = blocker_policy,
        };
        const Body = Elaboration.FromResidual(blocker_input, Program, .{ .label = "from-residual-cycle-blocker-map-body" });
        Body.certificate.check(
            blocker_input.policy,
            blocker_graph.evidenceRef(),
            blocker_report.evidenceRef(),
            blocker_certificate.evidenceRef(),
            Body.source_map,
            Body.effect_row,
            Body.trace_map,
            Body.normal_form,
            &.{},
            &.{},
        ) catch break :blk false;
        break :blk Body.normal_form.kind == .partial_with_blockers and
            Body.effect_row.blockers == 1 and
            Body.effect_row.unsupported_shapes == 0 and
            Body.source_map.entries.len == 1 and
            Body.source_map.entries[0].disposition == .blocked and
            Body.source_map.entries[0].source_ref.eql(blocked_shape_ref) and
            Body.source_map.entries[0].blocker_ref.?.eql(Evidence.refForBoundaryClosureBlocker(closure_blocker));
    };
    try std.testing.expect(cycle_blocker_not_shape);

    const blocked_plan_map_bound = comptime blk: {
        @setEvalBranchQuota(200_000);
        const blocker_graph = Closure.Graph.init("from-residual-blocked-plan-graph", &.{}, &.{}, &.{});
        const blocker_source_ref = source_ref;
        const blocked_shape = Closure.EffectShape.init(.{
            .program_label = "from-residual-blocked-plan-source",
            .kind = .operation,
            .site_index = 0,
            .protocol_label = "approval",
        });
        const plan_blocker = Evidence.BoundaryClosureBlocker{
            .tag = .unsupported_shape_planning,
            .subject = blocked_shape.evidenceRef(),
            .summary = "blocked static treaty plan has no elaborable route",
        };
        const blocked_plan = Closure.StaticTreatyPlan.init(.{
            .label = "from-residual-blocked-plan",
            .source_shape = blocked_shape,
            .selected_semantic_body = .unknown,
            .blockers = &.{plan_blocker},
        });
        const blocker_report = Closure.Report.init(.{
            .graph_fingerprint = blocker_graph.fingerprint,
            .root_program_refs = &.{blocker_source_ref},
            .effect_shape_count = 1,
            .blockers = &.{plan_blocker.toEvidenceBlocker()},
        });
        const blocker_certificate = Closure.Certificate.init(blocker_report, blocker_graph, Closure.Policy.auditOnly(), &.{blocked_plan.evidenceRef()});
        const blocker_input = Elaboration.Input{
            .closure_graph = blocker_graph,
            .closure_report = blocker_report,
            .closure_certificate = blocker_certificate,
            .static_treaty_plans = &.{blocked_plan},
            .source_program_ref = blocker_source_ref,
            .policy = Elaboration.Policy.auditOnly(),
        };
        const Body = Elaboration.FromResidual(blocker_input, Program, .{ .label = "from-residual-blocked-plan-body" });
        break :blk Body.source_map.entries.len == 1 and
            Body.source_map.entries[0].disposition == .blocked and
            Body.source_map.entries[0].static_treaty_plan_ref.?.eql(blocked_plan.evidenceRef());
    };
    try std.testing.expect(blocked_plan_map_bound);

    const blocked_host_intrinsic_valid = comptime blk: {
        @setEvalBranchQuota(200_000);
        const blocker_graph = Closure.Graph.init("blocked-host-intrinsic-graph", &.{}, &.{}, &.{});
        const blocked_shape = Closure.EffectShape.init(.{
            .program_label = "blocked-host-intrinsic-source",
            .kind = .operation,
            .site_index = 0,
            .protocol_label = "approval",
        });
        const intrinsic_ref = Evidence.refFor(Evidence.domains.host_intrinsic, 0xE1D251, .{ .label = "blocked-host-intrinsic" });
        const plan_blocker = Evidence.BoundaryClosureBlocker{
            .tag = .world_port_missing,
            .subject = blocked_shape.evidenceRef(),
            .summary = "host intrinsic route intentionally remains blocked",
        };
        const blocked_plan = Closure.StaticTreatyPlan.init(.{
            .label = "blocked-host-intrinsic-plan",
            .source_shape = blocked_shape,
            .selected_semantic_body = .host_intrinsic,
            .selected_intrinsic_ref = intrinsic_ref,
            .host_intrinsic = true,
            .blockers = &.{plan_blocker},
        });
        const blocker_report = Closure.Report.init(.{
            .graph_fingerprint = blocker_graph.fingerprint,
            .root_program_refs = &.{source_ref},
            .effect_shape_count = 1,
            .blockers = &.{plan_blocker.toEvidenceBlocker()},
        });
        const blocker_certificate = Closure.Certificate.init(blocker_report, blocker_graph, Closure.Policy.auditOnly(), &.{blocked_plan.evidenceRef()});
        const blocker_input = Elaboration.Input{
            .closure_graph = blocker_graph,
            .closure_report = blocker_report,
            .closure_certificate = blocker_certificate,
            .static_treaty_plans = &.{blocked_plan},
            .source_program_ref = source_ref,
            .policy = Elaboration.Policy.auditOnly(),
        };
        blocker_input.validate() catch break :blk false;
        break :blk true;
    };
    try std.testing.expect(blocked_host_intrinsic_valid);

    const blocked_provider_unlinked = comptime blk: {
        @setEvalBranchQuota(200_000);
        const blocker_graph = Closure.Graph.init("from-residual-blocked-provider-plan-graph", &.{}, &.{}, &.{});
        const blocker_source_ref = source_ref;
        const blocked_provider_ref = Evidence.refFor(Evidence.domains.provider_manifest, 0xE1D222, .{ .label = "blocked-provider" });
        const blocked_program_ref = Evidence.refFor(Evidence.domains.program_plan, 0xE1D223, .{ .label = "blocked-provider-program" });
        const blocked_shape = Closure.EffectShape.init(.{
            .program_label = "from-residual-blocked-provider-plan-source",
            .kind = .operation,
            .site_index = 0,
            .protocol_label = "approval",
        });
        const plan_blocker = Evidence.BoundaryClosureBlocker{
            .tag = .unsupported_shape_planning,
            .subject = blocked_shape.evidenceRef(),
            .summary = "blocked provider program route has no elaborable implementation",
        };
        const blocked_plan = Closure.StaticTreatyPlan.init(.{
            .label = "from-residual-blocked-provider-plan",
            .source_shape = blocked_shape,
            .selected_provider_ref = blocked_provider_ref,
            .selected_provider_offer_ref = blocked_provider_ref,
            .selected_capability_ref = blocked_provider_ref,
            .selected_semantic_body = .boundary_program,
            .selected_provider_program_ref = blocked_program_ref,
            .selected_provider_program_mapping_fingerprint = 0xE1D2_2301,
            .selected_provider_program_request_mapping_tag = "payload_to_args",
            .selected_provider_program_result_mapping_tag = "result_to_resume",
            .selected_provider_program_effect_shape_count = 0,
            .selected_provider_program_effect_shape_fingerprint = Evidence.fingerprintBoundaryEffectShapeSet(&.{}),
            .blockers = &.{plan_blocker},
        });
        const blocker_report = Closure.Report.init(.{
            .graph_fingerprint = blocker_graph.fingerprint,
            .root_program_refs = &.{blocker_source_ref},
            .provider_program_refs = &.{blocked_program_ref},
            .effect_shape_count = 1,
            .blockers = &.{plan_blocker.toEvidenceBlocker()},
        });
        const blocker_certificate = Closure.Certificate.init(blocker_report, blocker_graph, Closure.Policy.auditOnly(), &.{blocked_plan.evidenceRef()});
        const blocked_provider_programs = [_]Closure.ProviderProgram{.{
            .provider_ref = blocked_provider_ref,
            .program_ref = blocked_program_ref,
            .provider_program_mapping_fingerprint = blocked_plan.selected_provider_program_mapping_fingerprint,
            .request_mapping = .payload_to_args,
            .result_mapping = .result_to_resume,
            .effect_free = true,
        }};
        const blocker_input = Elaboration.Input{
            .closure_graph = blocker_graph,
            .closure_report = blocker_report,
            .closure_certificate = blocker_certificate,
            .static_treaty_plans = &.{blocked_plan},
            .source_program_ref = blocker_source_ref,
            .provider_programs = blocked_provider_programs[0..],
            .policy = Elaboration.Policy.auditOnly(),
        };
        const Body = Elaboration.FromResidual(blocker_input, Program, .{ .label = "from-residual-blocked-provider-plan-body" });
        break :blk Body.source_map.entries.len == 1 and
            Body.source_map.entries[0].disposition == .blocked and
            Body.source_map.entries[0].provider_program_ref == null and
            Body.effect_row.provider_program_links == 0 and
            Body.effect_row.linked_provider_programs == 0 and
            Body.effect_row.nested_provider_shapes_linked == 0 and
            Body.certificate.inlined_provider_program_refs.len == 0 and
            Body.certificate.summary_counts.provider_programs_linked == 0;
    };
    try std.testing.expect(blocked_provider_unlinked);

    const wildcard_world_port_matches_residual_site = comptime blk: {
        @setEvalBranchQuota(200_000);
        const shape_ref = Evidence.refFor(Evidence.domains.boundary_effect_shape, 0xE1D205, .{ .label = "approval.request" });
        const wildcard_port = Closure.WorldPort.init(.{
            .label = "wildcard-approval-world-port",
            .kind = .test_fixture,
            .effect_shape_ref = shape_ref,
        });
        const wildcard_ports = [_]Closure.WorldPort{wildcard_port};
        const wildcard_graph = Closure.Graph.init("wildcard-world-port-graph", &.{}, &.{}, &.{});
        const wildcard_source_ref = source_ref;
        const wildcard_report = Closure.Report.init(.{
            .graph_fingerprint = wildcard_graph.fingerprint,
            .root_program_refs = &.{wildcard_source_ref},
            .effect_shape_count = 1,
            .world_port_refs = &.{wildcard_port.evidenceRef()},
            .open_world_port_count = 1,
        });
        const wildcard_certificate = Closure.Certificate.init(wildcard_report, wildcard_graph, Closure.Policy.auditOnly(), &.{});
        const wildcard_input = Elaboration.Input{
            .closure_graph = wildcard_graph,
            .closure_report = wildcard_report,
            .closure_certificate = wildcard_certificate,
            .source_program_ref = wildcard_source_ref,
            .world_ports = wildcard_ports[0..],
            .policy = Elaboration.Policy.auditOnly(),
        };
        const Body = Elaboration.FromResidual(wildcard_input, closure_source_program, .{ .label = "wildcard-world-port-body" });
        break :blk Body.source_map.worldPortForResidualSite(closure_approval_request.index).?.eql(wildcard_port.evidenceRef());
    };
    try std.testing.expect(wildcard_world_port_matches_residual_site);

    const direct_world_port_source_site = comptime blk: {
        @setEvalBranchQuota(200_000);
        const source_site_index = closure_approval_request.index + 7;
        const direct_shape = Closure.EffectShape.init(.{
            .program_label = "direct-world-port-source",
            .kind = .operation,
            .site_index = source_site_index,
            .protocol_label = "approval",
            .protocol_op_fingerprint = closure_approval_request.fingerprint,
        });
        const direct_port = Closure.WorldPort.init(.{
            .label = "direct-world-port",
            .kind = .test_fixture,
            .effect_shape_ref = direct_shape.evidenceRef(),
            .supported_protocol_labels = &.{"approval"},
            .supported_site_indexes = &.{ source_site_index, closure_approval_request.index },
            .supported_protocol_op_fingerprints = &.{closure_approval_request.fingerprint},
        });
        const direct_graph = Closure.Graph.init("direct-world-port-source-site-graph", &.{}, &.{}, &.{});
        const direct_report = Closure.Report.init(.{
            .graph_fingerprint = direct_graph.fingerprint,
            .root_program_refs = &.{source_ref},
            .effect_shape_count = 1,
            .world_port_refs = &.{direct_port.evidenceRef()},
            .open_world_port_count = 1,
        });
        const direct_certificate = Closure.Certificate.init(direct_report, direct_graph, Closure.Policy.auditOnly(), &.{});
        const direct_input = Elaboration.Input{
            .closure_graph = direct_graph,
            .closure_report = direct_report,
            .closure_certificate = direct_certificate,
            .source_program_ref = source_ref,
            .world_ports = &.{direct_port},
            .policy = Elaboration.Policy.auditOnly(),
        };
        const Body = Elaboration.FromResidual(direct_input, closure_source_program, .{ .label = "direct-world-port-source-site-body" });
        break :blk Body.source_map.entries.len == 1 and
            Body.source_map.entries[0].source_ref.eql(direct_shape.evidenceRef()) and
            Body.source_map.entries[0].source_site_index.? == source_site_index and
            Body.source_map.entries[0].residual_site_index.? == closure_approval_request.index;
    };
    try std.testing.expect(direct_world_port_source_site);

    const shape_only_plan_port_lowers = comptime blk: {
        @setEvalBranchQuota(200_000);
        const shape_only_shape = Closure.EffectShape.init(.{
            .program_label = "shape-only-static-plan-source",
            .kind = .operation,
            .site_index = closure_approval_request.index,
            .protocol_label = "approval",
            .protocol_op_fingerprint = closure_approval_request.fingerprint,
        });
        const shape_only_plan = Closure.StaticTreatyPlan.init(.{
            .label = "shape-only-static-plan",
            .source_shape = shape_only_shape,
            .selected_semantic_body = .declarative,
        });
        const shape_only_port = Closure.WorldPort.init(.{
            .label = "shape-only-static-plan-world-port",
            .kind = .test_fixture,
            .effect_shape_ref = shape_only_shape.evidenceRef(),
            .supported_protocol_labels = &.{"approval"},
            .supported_site_indexes = &.{closure_approval_request.index},
            .supported_protocol_op_fingerprints = &.{closure_approval_request.fingerprint},
        });
        const shape_only_graph = Closure.Graph.init("shape-only-static-plan-world-graph", &.{}, &.{}, &.{});
        const shape_only_report = Closure.Report.init(.{
            .graph_fingerprint = shape_only_graph.fingerprint,
            .root_program_refs = &.{source_ref},
            .effect_shape_count = 1,
            .world_port_refs = &.{shape_only_port.evidenceRef()},
            .open_world_port_count = 1,
        });
        const shape_only_certificate = Closure.Certificate.init(shape_only_report, shape_only_graph, Closure.Policy.auditOnly(), &.{shape_only_plan.evidenceRef()});
        const shape_only_input = Elaboration.Input{
            .closure_graph = shape_only_graph,
            .closure_report = shape_only_report,
            .closure_certificate = shape_only_certificate,
            .static_treaty_plans = &.{shape_only_plan},
            .source_program_ref = source_ref,
            .world_ports = &.{shape_only_port},
            .policy = Elaboration.Policy.auditOnly(),
        };
        const Body = Elaboration.FromResidual(shape_only_input, closure_source_program, .{ .label = "shape-only-static-plan-world-body" });
        const missing_morphism_ref = Evidence.refFor(Evidence.domains.morphism_offer, 0xE1D2_8301, .{ .label = "missing-shape-only-morphism" });
        const missing_proof_plan = Closure.StaticTreatyPlan.init(.{
            .label = "shape-only-static-plan-missing-proof",
            .source_shape = shape_only_shape,
            .selected_semantic_body = .declarative,
            .selected_morphism_ref = missing_morphism_ref,
            .selected_morphism_semantic_body = .declarative,
            .selected_morphism_target_shape_ref = shape_only_shape.evidenceRef(),
            .selected_morphism_target_shape = shape_only_shape,
        });
        var missing_proof_entries = [_]Elaboration.SourceMap.Entry{Body.source_map.entries[0]};
        missing_proof_entries[0].static_treaty_plan_ref = missing_proof_plan.evidenceRef();
        missing_proof_entries[0].source_ref = shape_only_shape.evidenceRef();
        const missing_proof_map = Elaboration.SourceMap.init("shape-only-missing-proof-map", missing_proof_entries[0..], &.{});
        const missing_proof_trace_entries = [_]Elaboration.TraceMap.Entry{.{
            .source_ref = shape_only_shape.evidenceRef(),
            .residual_ref = shape_only_port.evidenceRef(),
            .trace_label = missing_proof_entries[0].label,
        }};
        const missing_proof_trace = Elaboration.TraceMap.init("shape-only-missing-proof-trace", missing_proof_trace_entries[0..]);
        const missing_proof_dependencies = [_]Evidence.Dependency{
            .{ .role = .closure_certificate, .ref = shape_only_certificate.evidenceRef() },
            .{ .role = .elaboration_source_map, .ref = missing_proof_map.evidenceRef() },
            .{ .role = .elaboration_trace_map, .ref = missing_proof_trace.evidenceRef() },
            .{ .role = .normal_form, .ref = Body.normal_form.evidenceRef() },
        };
        const missing_proof_certificate = Elaboration.Certificate.init(.{
            .elaborated_program_label = closure_source_program.contract.label,
            .source_program_ref = source_ref,
            .residual_program_ref = Body.certificate.residual_program_ref,
            .closure_certificate_ref = shape_only_certificate.evidenceRef(),
            .closure_graph_ref = shape_only_graph.evidenceRef(),
            .closure_report_ref = shape_only_report.evidenceRef(),
            .source_map_ref = missing_proof_map.evidenceRef(),
            .effect_row_ref = Body.effect_row.evidenceRef(),
            .trace_map_ref = missing_proof_trace.evidenceRef(),
            .normal_form_ref = Body.normal_form.evidenceRef(),
            .policy = shape_only_input.policy,
            .normal_form = Body.normal_form.kind,
            .selected_static_treaty_plan_refs = &.{missing_proof_plan.evidenceRef()},
            .world_port_refs = &.{shape_only_port.evidenceRef()},
            .residual_world_port_refs = &.{shape_only_port.evidenceRef()},
            .summary_counts = Body.certificate.summary_counts,
            .dependencies = missing_proof_dependencies[0..],
        });
        const missing_proof_rejected = reject: {
            missing_proof_certificate.check(
                shape_only_input.policy,
                shape_only_graph.evidenceRef(),
                shape_only_report.evidenceRef(),
                shape_only_certificate.evidenceRef(),
                missing_proof_map,
                Body.effect_row,
                missing_proof_trace,
                Body.normal_form,
                &.{missing_proof_plan},
                &.{shape_only_port},
            ) catch |err| break :reject err == error.BoundaryElaborationCertificateMismatch;
            break :reject false;
        };
        break :blk Body.source_map.entries.len == 1 and
            Body.source_map.entries[0].disposition == .world_port_lowered and
            Body.source_map.entries[0].world_port_ref.?.eql(shape_only_port.evidenceRef()) and
            Body.effect_row.world_ports == 1 and
            Body.normal_form.kind == .world_ports_only and
            missing_proof_rejected;
    };
    try std.testing.expect(shape_only_plan_port_lowers);

    const wildcard_shape_port_lowers = comptime blk: {
        @setEvalBranchQuota(200_000);
        const shape_only_shape = Closure.EffectShape.init(.{
            .program_label = "unbound-shape-only-static-plan-source",
            .kind = .operation,
            .site_index = closure_approval_request.index,
            .protocol_label = "approval",
            .protocol_op_fingerprint = closure_approval_request.fingerprint,
        });
        const shape_only_plan = Closure.StaticTreatyPlan.init(.{
            .label = "unbound-shape-only-static-plan",
            .source_shape = shape_only_shape,
            .selected_semantic_body = .declarative,
        });
        const broad_port = Closure.WorldPort.init(.{
            .label = "unbound-shape-only-static-plan-world-port",
            .kind = .test_fixture,
            .supported_protocol_labels = &.{"approval"},
            .supported_site_indexes = &.{closure_approval_request.index},
            .supported_protocol_op_fingerprints = &.{closure_approval_request.fingerprint},
        });
        const shape_only_graph = Closure.Graph.init("unbound-shape-only-static-plan-world-graph", &.{}, &.{}, &.{});
        const shape_only_report = Closure.Report.init(.{
            .graph_fingerprint = shape_only_graph.fingerprint,
            .root_program_refs = &.{source_ref},
            .effect_shape_count = 1,
            .world_port_refs = &.{broad_port.evidenceRef()},
            .open_world_port_count = 1,
        });
        const shape_only_certificate = Closure.Certificate.init(shape_only_report, shape_only_graph, Closure.Policy.auditOnly(), &.{shape_only_plan.evidenceRef()});
        const shape_only_input = Elaboration.Input{
            .closure_graph = shape_only_graph,
            .closure_report = shape_only_report,
            .closure_certificate = shape_only_certificate,
            .static_treaty_plans = &.{shape_only_plan},
            .source_program_ref = source_ref,
            .world_ports = &.{broad_port},
            .policy = Elaboration.Policy.auditOnly(),
        };
        const Body = Elaboration.FromResidual(shape_only_input, closure_source_program, .{ .label = "wildcard-shape-only-static-plan-world-body" });
        break :blk Body.source_map.entries.len == 1 and
            Body.source_map.entries[0].disposition == .world_port_lowered and
            Body.source_map.entries[0].world_port_ref.?.eql(broad_port.evidenceRef()) and
            Body.effect_row.world_ports == 1 and
            Body.normal_form.kind == .world_ports_only;
    };
    try std.testing.expect(wildcard_shape_port_lowers);

    const static_direct_blocker_bound = comptime blk: {
        @setEvalBranchQuota(200_000);
        const shape = Closure.EffectShape.init(.{
            .program_label = "static-plan-direct-blocker-source",
            .kind = .operation,
            .site_index = closure_approval_request.index,
            .protocol_label = "approval",
            .protocol_op_fingerprint = closure_approval_request.fingerprint,
        });
        const plan = Closure.StaticTreatyPlan.init(.{
            .label = "static-plan-with-direct-blocker",
            .source_shape = shape,
            .selected_semantic_body = .declarative,
        });
        const port = Closure.WorldPort.init(.{
            .label = "static-plan-direct-blocker-world-port",
            .kind = .test_fixture,
            .effect_shape_ref = shape.evidenceRef(),
            .supported_protocol_labels = &.{"approval"},
            .supported_site_indexes = &.{closure_approval_request.index},
            .supported_protocol_op_fingerprints = &.{closure_approval_request.fingerprint},
        });
        const direct_blocker = Evidence.boundaryClosureBlocker(.{
            .tag = .unsupported_shape_planning,
            .subject = Evidence.refFor(Evidence.domains.boundary_effect_shape, 0xE1D2_8201, .{ .label = "direct-report-blocker" }),
            .summary = "direct report blocker survives static plan source map",
        });
        const blocker_graph = Closure.Graph.init("static-plan-direct-blocker-graph", &.{}, &.{}, &.{});
        const blocker_report = Closure.Report.init(.{
            .graph_fingerprint = blocker_graph.fingerprint,
            .root_program_refs = &.{source_ref},
            .effect_shape_count = 2,
            .world_port_refs = &.{port.evidenceRef()},
            .open_world_port_count = 1,
            .blockers = &.{direct_blocker},
        });
        const blocker_certificate = Closure.Certificate.init(blocker_report, blocker_graph, Closure.Policy.auditOnly(), &.{plan.evidenceRef()});
        const blocker_input = Elaboration.Input{
            .closure_graph = blocker_graph,
            .closure_report = blocker_report,
            .closure_certificate = blocker_certificate,
            .static_treaty_plans = &.{plan},
            .source_program_ref = source_ref,
            .world_ports = &.{port},
            .policy = Elaboration.Policy.auditOnly(),
        };
        const Body = Elaboration.FromResidual(blocker_input, closure_source_program, .{ .label = "static-plan-direct-blocker-body" });
        Body.certificate.check(
            blocker_input.policy,
            blocker_graph.evidenceRef(),
            blocker_report.evidenceRef(),
            blocker_certificate.evidenceRef(),
            Body.source_map,
            Body.effect_row,
            Body.trace_map,
            Body.normal_form,
            &.{plan},
            &.{port},
        ) catch break :blk false;
        break :blk Body.source_map.entries.len == 2 and
            Body.source_map.entries[0].disposition == .world_port_lowered and
            Body.source_map.entries[1].disposition == .blocked and
            Body.source_map.entries[1].blocker_ref.?.eql(Evidence.refForBoundaryClosureBlocker(direct_blocker)) and
            Body.effect_row.source_effect_shapes == 2 and
            Body.effect_row.blockers == 1;
    };
    try std.testing.expect(static_direct_blocker_bound);

    const dup_direct_blocker_once = comptime blk: {
        @setEvalBranchQuota(200_000);
        const shape = Closure.EffectShape.init(.{
            .program_label = "duplicate-direct-blocker-source",
            .kind = .operation,
            .site_index = closure_approval_request.index,
            .protocol_label = "approval",
            .protocol_op_fingerprint = closure_approval_request.fingerprint,
        });
        const plan = Closure.StaticTreatyPlan.init(.{
            .label = "duplicate-direct-blocker-plan",
            .source_shape = shape,
            .selected_semantic_body = .declarative,
        });
        const port = Closure.WorldPort.init(.{
            .label = "duplicate-direct-blocker-world-port",
            .kind = .test_fixture,
            .effect_shape_ref = shape.evidenceRef(),
            .supported_protocol_labels = &.{"approval"},
            .supported_site_indexes = &.{closure_approval_request.index},
            .supported_protocol_op_fingerprints = &.{closure_approval_request.fingerprint},
        });
        const duplicate_blocker = Evidence.boundaryClosureBlocker(.{
            .tag = .provider_program_contract_missing,
            .subject = shape.evidenceRef(),
            .summary = "report-level blocker duplicates planned source shape",
        });
        const dup_graph = Closure.Graph.init("duplicate-direct-blocker-graph", &.{}, &.{}, &.{});
        const dup_report = Closure.Report.init(.{
            .graph_fingerprint = dup_graph.fingerprint,
            .root_program_refs = &.{source_ref},
            .effect_shape_count = 1,
            .world_port_refs = &.{port.evidenceRef()},
            .open_world_port_count = 1,
            .blockers = &.{duplicate_blocker},
        });
        const dup_certificate = Closure.Certificate.init(dup_report, dup_graph, Closure.Policy.auditOnly(), &.{plan.evidenceRef()});
        const dup_input = Elaboration.Input{
            .closure_graph = dup_graph,
            .closure_report = dup_report,
            .closure_certificate = dup_certificate,
            .static_treaty_plans = &.{plan},
            .source_program_ref = source_ref,
            .world_ports = &.{port},
            .policy = Elaboration.Policy.auditOnly(),
        };
        const Body = Elaboration.FromResidual(dup_input, closure_source_program, .{ .label = "duplicate-direct-blocker-body" });
        Body.certificate.check(
            dup_input.policy,
            dup_graph.evidenceRef(),
            dup_report.evidenceRef(),
            dup_certificate.evidenceRef(),
            Body.source_map,
            Body.effect_row,
            Body.trace_map,
            Body.normal_form,
            &.{plan},
            &.{port},
        ) catch break :blk false;
        break :blk Body.source_map.entries.len == 2 and
            Body.effect_row.source_effect_shapes == 1 and
            Body.effect_row.blockers == 1;
    };
    try std.testing.expect(dup_direct_blocker_once);

    const morphism_shape_port_targets = comptime blk: {
        @setEvalBranchQuota(200_000);
        const source_shape = Closure.EffectShape.init(.{
            .program_label = "morphism-shape-only-source",
            .kind = .operation,
            .site_index = closure_approval_request.index,
            .protocol_label = "approval",
            .protocol_op_fingerprint = closure_approval_request.fingerprint,
        });
        const target_op_fingerprint = closure_approval_request.fingerprint + 0x71;
        const target_shape = Closure.EffectShape.init(.{
            .program_label = "morphism-shape-only-source",
            .kind = .operation,
            .site_index = closure_approval_request.index,
            .protocol_label = "approval",
            .protocol_op_fingerprint = target_op_fingerprint,
            .usage_summary = "copyable",
        });
        const morphism = Program.Exchange.MorphismOffer{
            .label = "shape-only-target-morphism",
            .source_protocol_op_fingerprint = closure_approval_request.fingerprint,
            .target_protocol_op_fingerprint = target_op_fingerprint,
            .pipeline_fingerprint = 0xE1D2_7101,
        };
        const pipeline_ref = Evidence.refFor(Evidence.domains.pipeline, morphism.pipeline_fingerprint.?, .{ .label = "shape-only-target-pipeline" });
        const morphism_dependencies = [_]Evidence.Dependency{
            .{ .role = .morphism, .ref = morphism.evidenceRef() },
            .{ .role = .pipeline, .ref = pipeline_ref },
        };
        const morphism_plan = Closure.StaticTreatyPlan.init(.{
            .label = "morphism-shape-only-static-plan",
            .source_shape = source_shape,
            .selected_morphism_ref = morphism.evidenceRef(),
            .selected_morphism_target_shape_ref = target_shape.evidenceRef(),
            .selected_morphism_target_shape = target_shape,
            .selected_morphism_semantic_body = .pipeline,
            .selected_semantic_body = .declarative,
            .dependencies = morphism_dependencies[0..],
        });
        const target_port = Closure.WorldPort.init(.{
            .label = "morphism-shape-only-target-world-port",
            .kind = .test_fixture,
            .effect_shape_ref = target_shape.evidenceRef(),
            .supported_protocol_labels = &.{"approval"},
            .supported_site_indexes = &.{closure_approval_request.index},
        });
        const morphism_graph = Closure.Graph.init("morphism-shape-only-world-graph", &.{}, &.{}, &.{});
        const morphism_report = Closure.Report.init(.{
            .graph_fingerprint = morphism_graph.fingerprint,
            .root_program_refs = &.{source_ref},
            .effect_shape_count = 1,
            .world_port_refs = &.{target_port.evidenceRef()},
            .open_world_port_count = 1,
        });
        const morphism_certificate = Closure.Certificate.init(morphism_report, morphism_graph, Closure.Policy.auditOnly(), &.{morphism_plan.evidenceRef()});
        const morphism_input = Elaboration.Input{
            .closure_graph = morphism_graph,
            .closure_report = morphism_report,
            .closure_certificate = morphism_certificate,
            .static_treaty_plans = &.{morphism_plan},
            .source_program_ref = source_ref,
            .world_ports = &.{target_port},
            .morphism_offers = &.{morphism},
            .morphism_offer_refs = &.{morphism.evidenceRef()},
            .pipeline_adapter_refs = &.{pipeline_ref},
            .policy = Elaboration.Policy.auditOnly(),
        };
        const unproved_morphism_plan = Closure.StaticTreatyPlan.init(.{
            .label = "unproved-morphism-shape-only-static-plan",
            .source_shape = source_shape,
            .selected_morphism_ref = morphism.evidenceRef(),
            .selected_morphism_target_shape_ref = target_shape.evidenceRef(),
            .selected_morphism_target_shape = target_shape,
            .selected_morphism_semantic_body = .pipeline,
            .selected_semantic_body = .declarative,
        });
        const unproved_morphism_certificate = Closure.Certificate.init(morphism_report, morphism_graph, Closure.Policy.auditOnly(), &.{unproved_morphism_plan.evidenceRef()});
        const unproved_morphism_input = Elaboration.Input{
            .closure_graph = morphism_graph,
            .closure_report = morphism_report,
            .closure_certificate = unproved_morphism_certificate,
            .static_treaty_plans = &.{unproved_morphism_plan},
            .source_program_ref = source_ref,
            .world_ports = &.{target_port},
            .morphism_offers = &.{morphism},
            .policy = Elaboration.Policy.auditOnly(),
        };
        const unproved_rejected = reject: {
            unproved_morphism_input.validate() catch |err|
                break :reject err == error.BoundaryElaborationBlocked;
            break :reject false;
        };
        if (!unproved_rejected) break :blk false;
        const Body = Elaboration.FromResidual(morphism_input, closure_source_program, .{ .label = "morphism-shape-only-world-body" });
        Body.certificate.check(
            morphism_input.policy,
            morphism_graph.evidenceRef(),
            morphism_report.evidenceRef(),
            morphism_certificate.evidenceRef(),
            Body.source_map,
            Body.effect_row,
            Body.trace_map,
            Body.normal_form,
            &.{morphism_plan},
            &.{target_port},
        ) catch break :blk false;
        break :blk Body.source_map.entries.len == 1 and
            Body.source_map.entries[0].disposition == .world_port_lowered and
            Body.source_map.entries[0].source_ref.eql(target_shape.evidenceRef()) and
            Body.source_map.entries[0].world_port_ref.?.eql(target_port.evidenceRef()) and
            Body.effect_row.world_ports == 1 and
            Body.normal_form.kind == .world_ports_only;
    };
    try std.testing.expect(morphism_shape_port_targets);

    const morphism_target_ref_rejected = comptime blk: {
        @setEvalBranchQuota(200_000);
        const source_shape = Closure.EffectShape.init(.{
            .program_label = "morphism-shape-only-missing-target-source",
            .kind = .operation,
            .site_index = closure_approval_request.index,
            .protocol_label = "approval",
            .protocol_op_fingerprint = closure_approval_request.fingerprint,
        });
        const target_op_fingerprint = closure_approval_request.fingerprint + 0x73;
        const target_shape = Closure.EffectShape.init(.{
            .program_label = "morphism-shape-only-missing-target-source",
            .kind = .operation,
            .site_index = closure_approval_request.index,
            .protocol_label = "approval",
            .protocol_op_fingerprint = target_op_fingerprint,
            .usage_summary = "copyable",
        });
        const morphism = Program.Exchange.MorphismOffer{
            .label = "shape-only-missing-target-morphism",
            .source_protocol_op_fingerprint = closure_approval_request.fingerprint,
            .target_protocol_op_fingerprint = target_op_fingerprint,
            .pipeline_fingerprint = 0xE1D2_7301,
        };
        const morphism_plan = Closure.StaticTreatyPlan.init(.{
            .label = "morphism-shape-only-missing-target-plan",
            .source_shape = source_shape,
            .selected_morphism_ref = morphism.evidenceRef(),
            .selected_morphism_semantic_body = .pipeline,
            .selected_semantic_body = .declarative,
        });
        const pipeline_ref = Evidence.refFor(Evidence.domains.pipeline, morphism.pipeline_fingerprint.?, .{ .label = "shape-only-missing-target-pipeline" });
        const forged_dependencies = [_]Evidence.Dependency{
            .{ .role = .morphism, .ref = morphism.evidenceRef() },
            .{ .role = .pipeline, .ref = pipeline_ref },
        };
        const forged_morphism_plan = Closure.StaticTreatyPlan.init(.{
            .label = "morphism-shape-only-forged-target-ref-plan",
            .source_shape = source_shape,
            .selected_morphism_ref = morphism.evidenceRef(),
            .selected_morphism_target_shape_ref = target_shape.evidenceRef(),
            .selected_morphism_semantic_body = .pipeline,
            .selected_semantic_body = .declarative,
            .dependencies = forged_dependencies[0..],
        });
        const target_port = Closure.WorldPort.init(.{
            .label = "morphism-shape-only-missing-target-port",
            .kind = .test_fixture,
            .effect_shape_ref = target_shape.evidenceRef(),
            .supported_protocol_labels = &.{"approval"},
            .supported_site_indexes = &.{closure_approval_request.index},
        });
        const morphism_graph = Closure.Graph.init("morphism-shape-only-missing-target-graph", &.{}, &.{}, &.{});
        const morphism_report = Closure.Report.init(.{
            .graph_fingerprint = morphism_graph.fingerprint,
            .root_program_refs = &.{source_ref},
            .effect_shape_count = 1,
            .world_port_refs = &.{target_port.evidenceRef()},
            .open_world_port_count = 1,
        });
        const morphism_certificate = Closure.Certificate.init(morphism_report, morphism_graph, Closure.Policy.auditOnly(), &.{morphism_plan.evidenceRef()});
        const morphism_input = Elaboration.Input{
            .closure_graph = morphism_graph,
            .closure_report = morphism_report,
            .closure_certificate = morphism_certificate,
            .static_treaty_plans = &.{morphism_plan},
            .source_program_ref = source_ref,
            .world_ports = &.{target_port},
            .morphism_offers = &.{morphism},
            .policy = Elaboration.Policy.auditOnly(),
        };
        morphism_input.validate() catch |err| break :blk err == error.BoundaryElaborationBlocked;
        const forged_entries = [_]Elaboration.SourceMap.Entry{.{
            .source_ref = target_shape.evidenceRef(),
            .residual_ref = source_ref,
            .source_site_index = closure_approval_request.index,
            .residual_site_index = closure_approval_request.index,
            .static_treaty_plan_ref = forged_morphism_plan.evidenceRef(),
            .world_port_ref = target_port.evidenceRef(),
            .disposition = .world_port_lowered,
            .label = "forged morphism target world port",
        }};
        const forged_map = Elaboration.SourceMap.init("morphism-shape-only-forged-target-ref-map", forged_entries[0..], &.{});
        const forged_trace_entries = [_]Elaboration.TraceMap.Entry{.{
            .source_ref = target_shape.evidenceRef(),
            .residual_ref = target_port.evidenceRef(),
            .trace_label = forged_entries[0].label,
        }};
        const forged_trace = Elaboration.TraceMap.init("morphism-shape-only-forged-target-ref-trace", forged_trace_entries[0..]);
        const forged_row = Elaboration.EffectRow.init(.{
            .label = "morphism-shape-only-forged-target-ref-row",
            .source_program_ref = source_ref,
            .residual_program_ref = source_ref,
            .normal_form = .world_ports_only,
            .source_effect_shapes = 1,
            .world_ports = 1,
        });
        const forged_normal_form = Elaboration.NormalForm.init(
            "morphism-shape-only-forged-target-ref-normal-form",
            .world_ports_only,
            morphism_certificate.evidenceRef(),
            forged_row.evidenceRef(),
            0,
        );
        const forged_certificate = Elaboration.Certificate.init(.{
            .elaborated_program_label = closure_source_program.contract.label,
            .source_program_ref = source_ref,
            .residual_program_ref = source_ref,
            .closure_certificate_ref = morphism_certificate.evidenceRef(),
            .closure_graph_ref = morphism_graph.evidenceRef(),
            .closure_report_ref = morphism_report.evidenceRef(),
            .source_map_ref = forged_map.evidenceRef(),
            .effect_row_ref = forged_row.evidenceRef(),
            .trace_map_ref = forged_trace.evidenceRef(),
            .normal_form_ref = forged_normal_form.evidenceRef(),
            .policy = morphism_input.policy,
            .normal_form = forged_normal_form.kind,
            .selected_static_treaty_plan_refs = &.{forged_morphism_plan.evidenceRef()},
            .world_port_refs = &.{target_port.evidenceRef()},
            .residual_world_port_refs = &.{target_port.evidenceRef()},
            .summary_counts = .{
                .world_ports_emitted = 1,
            },
        });
        const forged_target_ref_rejected = reject: {
            forged_certificate.check(
                morphism_input.policy,
                morphism_graph.evidenceRef(),
                morphism_report.evidenceRef(),
                morphism_certificate.evidenceRef(),
                forged_map,
                forged_row,
                forged_trace,
                forged_normal_form,
                &.{forged_morphism_plan},
                &.{target_port},
            ) catch |err| break :reject err == error.BoundaryElaborationCertificateMismatch;
            break :reject false;
        };
        break :blk forged_target_ref_rejected;
    };
    try std.testing.expect(morphism_target_ref_rejected);

    const morphism_intrinsic_targets = comptime blk: {
        @setEvalBranchQuota(200_000);
        const source_shape = Closure.EffectShape.init(.{
            .program_label = "morphism-intrinsic-source",
            .kind = .operation,
            .site_index = closure_approval_request.index,
            .protocol_label = "approval",
            .protocol_op_fingerprint = closure_approval_request.fingerprint,
        });
        const target_op_fingerprint = closure_approval_request.fingerprint + 0x72;
        const target_shape = Closure.EffectShape.init(.{
            .program_label = "morphism-intrinsic-source",
            .kind = .operation,
            .site_index = closure_approval_request.index,
            .protocol_label = "approval",
            .protocol_op_fingerprint = target_op_fingerprint,
            .usage_summary = "copyable",
        });
        const morphism = Program.Exchange.MorphismOffer{
            .label = "intrinsic-target-morphism",
            .source_protocol_op_fingerprint = closure_approval_request.fingerprint,
            .target_protocol_op_fingerprint = target_op_fingerprint,
            .dynamic_morphism_fingerprint = 0xE1D2_7201,
        };
        const intrinsic_ref = morphism.hostIntrinsicRef().?;
        const morphism_dependencies = [_]Evidence.Dependency{.{
            .role = .morphism,
            .ref = morphism.evidenceRef(),
        }};
        const morphism_plan = Closure.StaticTreatyPlan.init(.{
            .label = "morphism-intrinsic-static-plan",
            .source_shape = source_shape,
            .selected_morphism_ref = morphism.evidenceRef(),
            .selected_morphism_target_shape_ref = target_shape.evidenceRef(),
            .selected_morphism_target_shape = target_shape,
            .selected_morphism_semantic_body = .host_intrinsic,
            .selected_morphism_intrinsic_ref = intrinsic_ref,
            .selected_semantic_body = .declarative,
            .dependencies = morphism_dependencies[0..],
        });
        const target_port = Closure.WorldPort.init(.{
            .label = "morphism-intrinsic-target-world-port",
            .kind = .test_fixture,
            .exposed_intrinsic_ref = intrinsic_ref,
            .supported_protocol_labels = &.{"approval"},
            .supported_site_indexes = &.{closure_approval_request.index},
        });
        const morphism_graph = Closure.Graph.init("morphism-intrinsic-world-graph", &.{}, &.{}, &.{});
        const morphism_report = Closure.Report.init(.{
            .graph_fingerprint = morphism_graph.fingerprint,
            .root_program_refs = &.{source_ref},
            .effect_shape_count = 1,
            .world_port_refs = &.{target_port.evidenceRef()},
            .open_world_port_count = 1,
        });
        const morphism_certificate = Closure.Certificate.init(morphism_report, morphism_graph, Closure.Policy.auditOnly(), &.{morphism_plan.evidenceRef()});
        const morphism_input = Elaboration.Input{
            .closure_graph = morphism_graph,
            .closure_report = morphism_report,
            .closure_certificate = morphism_certificate,
            .static_treaty_plans = &.{morphism_plan},
            .source_program_ref = source_ref,
            .world_ports = &.{target_port},
            .morphism_offers = &.{morphism},
            .morphism_offer_refs = &.{morphism.evidenceRef()},
            .policy = Elaboration.Policy.auditOnly(),
        };
        const Body = Elaboration.FromResidual(morphism_input, closure_source_program, .{ .label = "morphism-intrinsic-world-body" });
        Body.certificate.check(
            morphism_input.policy,
            morphism_graph.evidenceRef(),
            morphism_report.evidenceRef(),
            morphism_certificate.evidenceRef(),
            Body.source_map,
            Body.effect_row,
            Body.trace_map,
            Body.normal_form,
            &.{morphism_plan},
            &.{target_port},
        ) catch break :blk false;
        break :blk Body.source_map.entries.len == 1 and
            Body.source_map.entries[0].disposition == .world_port_lowered and
            Body.source_map.entries[0].source_ref.eql(target_shape.evidenceRef()) and
            Body.source_map.entries[0].world_port_ref.?.eql(target_port.evidenceRef()) and
            Body.effect_row.world_ports == 1 and
            Body.normal_form.kind == .world_ports_only;
    };
    try std.testing.expect(morphism_intrinsic_targets);

    const site_index_ports_ok = comptime blk: {
        @setEvalBranchQuota(200_000);
        const MultiClosure = closure_multi_yield_program.BoundaryClosure;
        const MultiElaboration = MultiClosure.Elaboration;
        const first_site = closure_multi_yield_program.contract.session.yield_sites[0];
        const second_site = closure_multi_yield_program.contract.session.yield_sites[1];
        const multi_source_ref = closure_multi_yield_program.Evidence.refFor(
            closure_multi_yield_program.Evidence.domains.program_plan,
            closure_multi_yield_program.compiled_plan.hash(),
            .{ .label = closure_multi_yield_program.contract.label },
        );
        const first_port = MultiClosure.WorldPort.init(.{
            .label = "first-duplicate-yield-world-port",
            .kind = .test_fixture,
            .supported_protocol_labels = &.{"approval"},
            .supported_site_indexes = &.{first_site.index},
        });
        const second_port = MultiClosure.WorldPort.init(.{
            .label = "second-duplicate-yield-world-port",
            .kind = .test_fixture,
            .supported_protocol_labels = &.{"approval"},
            .supported_site_indexes = &.{second_site.index},
        });
        const multi_graph = MultiClosure.Graph.init("duplicate-yield-world-port-graph", &.{}, &.{}, &.{});
        const multi_report = MultiClosure.Report.init(.{
            .graph_fingerprint = multi_graph.fingerprint,
            .root_program_refs = &.{multi_source_ref},
            .effect_shape_count = 2,
            .world_port_refs = &.{ first_port.evidenceRef(), second_port.evidenceRef() },
            .open_world_port_count = 2,
        });
        const multi_certificate = MultiClosure.Certificate.init(multi_report, multi_graph, MultiClosure.Policy.auditOnly(), &.{});
        const multi_input = MultiElaboration.Input{
            .closure_graph = multi_graph,
            .closure_report = multi_report,
            .closure_certificate = multi_certificate,
            .source_program_ref = multi_source_ref,
            .world_ports = &.{ first_port, second_port },
            .policy = MultiElaboration.Policy.auditOnly(),
        };
        const Body = MultiElaboration.FromResidual(multi_input, closure_multi_yield_program, .{ .label = "duplicate-yield-world-port-body" });
        break :blk Body.source_map.worldPortForResidualSite(first_site.index).?.eql(first_port.evidenceRef()) and
            Body.source_map.worldPortForResidualSite(second_site.index).?.eql(second_port.evidenceRef());
    };
    try std.testing.expect(site_index_ports_ok);

    const multi_site_descriptor_ok = comptime blk: {
        @setEvalBranchQuota(200_000);
        const MultiClosure = closure_multi_yield_program.BoundaryClosure;
        const MultiElaboration = MultiClosure.Elaboration;
        const first_site = closure_multi_yield_program.contract.session.yield_sites[0];
        const second_site = closure_multi_yield_program.contract.session.yield_sites[1];
        const multi_source_ref = closure_multi_yield_program.Evidence.refFor(
            closure_multi_yield_program.Evidence.domains.program_plan,
            closure_multi_yield_program.compiled_plan.hash(),
            .{ .label = closure_multi_yield_program.contract.label },
        );
        const shared_port = MultiClosure.WorldPort.init(.{
            .label = "shared-multi-yield-world-port",
            .kind = .test_fixture,
            .supported_protocol_labels = &.{"approval"},
            .supported_site_indexes = &.{ first_site.index, second_site.index },
        });
        const shared_port_refs = [_]Evidence.Ref{ shared_port.evidenceRef(), shared_port.evidenceRef() };
        const multi_graph = MultiClosure.Graph.init("shared-yield-world-port-graph", &.{}, &.{}, &.{});
        const multi_report = MultiClosure.Report.init(.{
            .graph_fingerprint = multi_graph.fingerprint,
            .root_program_refs = &.{multi_source_ref},
            .effect_shape_count = 2,
            .world_port_refs = shared_port_refs[0..],
            .open_world_port_count = 2,
        });
        const multi_certificate = MultiClosure.Certificate.init(multi_report, multi_graph, MultiClosure.Policy.auditOnly(), &.{});
        const multi_input = MultiElaboration.Input{
            .closure_graph = multi_graph,
            .closure_report = multi_report,
            .closure_certificate = multi_certificate,
            .source_program_ref = multi_source_ref,
            .world_ports = &.{shared_port},
            .policy = MultiElaboration.Policy.auditOnly(),
        };
        const Body = MultiElaboration.FromResidual(multi_input, closure_multi_yield_program, .{ .label = "shared-yield-world-port-body" });
        break :blk Body.source_map.worldPortForResidualSite(first_site.index).?.eql(shared_port.evidenceRef()) and
            Body.source_map.worldPortForResidualSite(second_site.index).?.eql(shared_port.evidenceRef());
    };
    try std.testing.expect(multi_site_descriptor_ok);

    const planned_shared_world_port_ok = comptime blk: {
        @setEvalBranchQuota(200_000);
        const MultiClosure = closure_multi_yield_program.BoundaryClosure;
        const MultiElaboration = MultiClosure.Elaboration;
        const MultiEvidence = closure_multi_yield_program.Evidence;
        const first_site = closure_multi_yield_program.contract.session.yield_sites[0];
        const second_site = closure_multi_yield_program.contract.session.yield_sites[1];
        const multi_source_ref = MultiEvidence.refFor(
            MultiEvidence.domains.program_plan,
            closure_multi_yield_program.compiled_plan.hash(),
            .{ .label = closure_multi_yield_program.contract.label },
        );
        const intrinsic_ref = MultiEvidence.refFor(MultiEvidence.domains.host_intrinsic, 0xE1D2_2A01, .{ .label = "shared-planned-world-port-intrinsic" });
        const first_shape = MultiClosure.EffectShape.init(.{
            .program_label = closure_multi_yield_program.contract.label,
            .plan_hash = closure_multi_yield_program.compiled_plan.hash(),
            .kind = .operation,
            .site_index = first_site.index,
            .protocol_label = "approval",
        });
        const second_shape = MultiClosure.EffectShape.init(.{
            .program_label = closure_multi_yield_program.contract.label,
            .plan_hash = closure_multi_yield_program.compiled_plan.hash(),
            .kind = .operation,
            .site_index = second_site.index,
            .protocol_label = "approval",
        });
        const first_plan = MultiClosure.StaticTreatyPlan.init(.{
            .label = "first-shared-world-port-plan",
            .source_shape = first_shape,
            .selected_semantic_body = .host_intrinsic,
            .selected_intrinsic_ref = intrinsic_ref,
            .host_intrinsic = true,
        });
        const second_plan = MultiClosure.StaticTreatyPlan.init(.{
            .label = "second-shared-world-port-plan",
            .source_shape = second_shape,
            .selected_semantic_body = .host_intrinsic,
            .selected_intrinsic_ref = intrinsic_ref,
            .host_intrinsic = true,
        });
        const shared_port = MultiClosure.WorldPort.init(.{
            .label = "shared-planned-world-port",
            .kind = .test_fixture,
            .exposed_intrinsic_ref = intrinsic_ref,
            .supported_protocol_labels = &.{"approval"},
            .supported_site_indexes = &.{ first_site.index, second_site.index },
        });
        const shared_port_refs = [_]MultiEvidence.Ref{ shared_port.evidenceRef(), shared_port.evidenceRef() };
        const multi_graph = MultiClosure.Graph.init("shared-planned-world-port-graph", &.{}, &.{}, &.{});
        const multi_report = MultiClosure.Report.init(.{
            .graph_fingerprint = multi_graph.fingerprint,
            .root_program_refs = &.{multi_source_ref},
            .effect_shape_count = 2,
            .world_port_refs = shared_port_refs[0..],
            .open_world_port_count = 2,
        });
        const multi_certificate = MultiClosure.Certificate.init(multi_report, multi_graph, MultiClosure.Policy.auditOnly(), &.{ first_plan.evidenceRef(), second_plan.evidenceRef() });
        const multi_input = MultiElaboration.Input{
            .closure_graph = multi_graph,
            .closure_report = multi_report,
            .closure_certificate = multi_certificate,
            .static_treaty_plans = &.{ first_plan, second_plan },
            .source_program_ref = multi_source_ref,
            .world_ports = &.{shared_port},
            .policy = MultiElaboration.Policy.auditOnly(),
        };
        const Body = MultiElaboration.FromResidual(multi_input, closure_multi_yield_program, .{ .label = "shared-planned-world-port-body" });
        break :blk Body.source_map.worldPortForResidualSite(first_site.index).?.eql(shared_port.evidenceRef()) and
            Body.source_map.worldPortForResidualSite(second_site.index).?.eql(shared_port.evidenceRef());
    };
    try std.testing.expect(planned_shared_world_port_ok);

    const merged_world_port_site = comptime blk: {
        @setEvalBranchQuota(200_000);
        const source_site_index = closure_approval_request.index + 7;
        const source_protocol_fingerprint = closure_approval_request.fingerprint;
        const world_shape = Closure.EffectShape.init(.{
            .program_label = "wildcard-source",
            .kind = .operation,
            .site_index = source_site_index,
            .protocol_label = "approval",
            .protocol_op_fingerprint = source_protocol_fingerprint,
            .mode = "transform",
            .semantic_label = "approval.request",
            .value_ref = Evidence.BoundaryValueRef.fromValueRef(closure_approval_request.payload_ref),
            .expected_resume_ref = Evidence.BoundaryValueRef.fromValueRef(closure_approval_request.resume_ref),
        });
        const world_plan = Closure.StaticTreatyPlan.init(.{
            .label = "world-port-plan",
            .source_shape = world_shape,
            .selected_semantic_body = .host_intrinsic,
            .selected_intrinsic_ref = Evidence.refFor(Evidence.domains.host_intrinsic, 0xE1D21C, .{ .label = "planned-world-port-intrinsic" }),
            .host_intrinsic = true,
        });
        const world_port = Closure.WorldPort.init(.{
            .label = "planned-world-port",
            .kind = .test_fixture,
            .effect_shape_ref = world_shape.evidenceRef(),
            .exposed_intrinsic_ref = world_plan.selected_intrinsic_ref,
            .supported_protocol_labels = &.{"approval"},
            .supported_site_indexes = &.{ source_site_index, closure_approval_request.index },
            .supported_protocol_op_fingerprints = &.{ source_protocol_fingerprint, closure_approval_request.fingerprint },
        });
        const world_graph = Closure.Graph.init("planned-world-port-graph", &.{}, &.{}, &.{});
        const world_source_ref = source_ref;
        const world_report = Closure.Report.init(.{
            .graph_fingerprint = world_graph.fingerprint,
            .root_program_refs = &.{world_source_ref},
            .effect_shape_count = 1,
            .world_port_refs = &.{world_port.evidenceRef()},
            .open_world_port_count = 1,
        });
        const world_certificate = Closure.Certificate.init(world_report, world_graph, Closure.Policy.auditOnly(), &.{world_plan.evidenceRef()});
        const world_input = Elaboration.Input{
            .closure_graph = world_graph,
            .closure_report = world_report,
            .closure_certificate = world_certificate,
            .static_treaty_plans = &.{world_plan},
            .source_program_ref = world_source_ref,
            .world_ports = &.{world_port},
            .policy = Elaboration.Policy.auditOnly(),
        };
        const Body = Elaboration.FromResidual(world_input, closure_source_program, .{ .label = "planned-world-port-body" });
        var target_policy = Elaboration.Target.Policy.auditOnly();
        target_policy.elaboration_policy.allow_intrinsic_world_ports = false;
        target_policy.fail_on_schema_mismatch = true;
        target_policy.preserve_source_coordinates = true;
        const Target = Elaboration.Target.compileComptime(.{
            .label = "planned-world-port-target-body",
            .input = world_input,
            .residual_program = closure_source_program,
            .policy = target_policy,
        });
        var label_elided_policy = target_policy;
        label_elided_policy.preserve_semantic_labels = false;
        const LabelElidedTarget = Elaboration.Target.compileComptime(.{
            .label = "planned-world-port-target-body-label-elided",
            .input = world_input,
            .residual_program = closure_source_program,
            .policy = label_elided_policy,
        });
        var custom_world_policy = Elaboration.Target.Policy.strictClosed();
        custom_world_policy.allow_world_ports = true;
        custom_world_policy.reject_host_intrinsic_internal_routes = false;
        custom_world_policy.require_checked_closure_certificate = false;
        custom_world_policy.elaboration_policy.reject_dynamic_intrinsic_mappers = false;
        const CustomWorldTarget = Elaboration.Target.compileComptime(.{
            .label = "planned-world-port-custom-target-policy",
            .input = world_input,
            .residual_program = closure_source_program,
            .policy = custom_world_policy,
        });
        Target.assertNormalForm(.world_ports_only);
        CustomWorldTarget.assertNormalForm(.world_ports_only);
        Target.assertWorldSurfaceReady();
        CustomWorldTarget.assertWorldSurfaceReady();
        Target.assertNoSearchHotPath();
        const Wrapped = boundary.program("planned-world-port-wrapped", closure_fixture_handlers, Body);
        break :blk Body.source_map.entries.len == 1 and
            Target.Body.source_map.entries.len == Body.source_map.entries.len and
            CustomWorldTarget.WorldPortTable.entries.len == 1 and
            Target.WorldSurface.world_port_count == 1 and
            Target.WorldPortTable.entries.len == 1 and
            Target.WorldPortTable.entries[0].world_port_id == 0 and
            Target.WorldDispatchTable.entries[0].residual_site_index == closure_approval_request.index and
            Target.WorldValueTable.entries.len == 3 and
            Target.WorldPortTable.entries[0].semantic_label != null and
            LabelElidedTarget.WorldPortTable.entries[0].semantic_label == null and
            Target.replay_key_recipe.surface_ref.eql(Target.WorldSurface.replayScopeRef()) and
            std.mem.eql(u8, Target.replay_key_recipe.components[0], "world_surface_scope_fingerprint") and
            Target.Certificate.world_surface_ref.eql(Target.WorldSurface.evidenceRef()) and
            Target.Certificate.normalization_certificate_ref.?.eql(Target.NormalizationCertificate.evidenceRef()) and
            Target.NormalizationTrace.rewrite_steps.len == 1 and
            Target.NormalizationTrace.residual_world_port_refs.len == 1 and
            Target.NormalizationTrace.rewrite_steps[0].world_port_ref.?.eql(world_port.evidenceRef()) and
            std.mem.eql(u8, Target.NormalizationTrace.rewrite_steps[0].summary, "residual_world_port") and
            Body.effect_row.source_effect_shapes == 1 and
            Body.effect_row.closed_effect_shapes == 0 and
            world_shape.result_ref == null and
            Body.source_map.entries[0].source_site_index.? == source_site_index and
            Body.source_map.entries[0].residual_site_index.? == closure_approval_request.index and
            Body.source_map.worldPortForResidualSite(closure_approval_request.index).?.eql(world_port.evidenceRef()) and
            Wrapped.protocol.operation_site_metadata.len == 1 and
            Wrapped.protocol.operation_site_metadata[0].semantic_label != null and
            std.mem.eql(u8, Wrapped.protocol.operation_site_metadata[0].semantic_label.?, "approval.request");
    };
    try std.testing.expect(merged_world_port_site);

    const direct_host_world_port_selection_uses_intrinsic = comptime blk: {
        @setEvalBranchQuota(200_000);
        const DualClosure = closure_dual_world_port_program.BoundaryClosure;
        const DualElaboration = DualClosure.Elaboration;
        const DualEvidence = closure_dual_world_port_program.Evidence;
        const dual_source_ref = DualEvidence.refFor(DualEvidence.domains.program_plan, closure_dual_world_port_program.compiled_plan.hash(), .{ .label = closure_dual_world_port_program.contract.label });
        const source_site_index = closure_dual_second.index;
        const direct_shape = DualClosure.EffectShape.init(.{
            .program_label = closure_dual_world_port_program.contract.label,
            .plan_hash = closure_dual_world_port_program.compiled_plan.hash(),
            .kind = .operation,
            .site_index = source_site_index,
            .protocol_label = "approval-dual",
        });
        const selected_intrinsic_ref = DualEvidence.refFor(DualEvidence.domains.host_intrinsic, 0xE1D21D, .{ .label = "selected-direct-world-intrinsic" });
        const other_intrinsic_ref = DualEvidence.refFor(DualEvidence.domains.host_intrinsic, 0xE1D21E, .{ .label = "other-direct-world-intrinsic" });
        const other_plan = DualClosure.StaticTreatyPlan.init(.{
            .label = "other-direct-host-world-plan",
            .source_shape = direct_shape,
            .selected_semantic_body = .host_intrinsic,
            .selected_intrinsic_ref = other_intrinsic_ref,
            .host_intrinsic = true,
        });
        const selected_plan = DualClosure.StaticTreatyPlan.init(.{
            .label = "selected-direct-host-world-plan",
            .source_shape = direct_shape,
            .selected_semantic_body = .host_intrinsic,
            .selected_intrinsic_ref = selected_intrinsic_ref,
            .host_intrinsic = true,
        });
        const other_port = DualClosure.WorldPort.init(.{
            .label = "other-direct-world-port",
            .kind = .test_fixture,
            .effect_shape_ref = direct_shape.evidenceRef(),
            .exposed_intrinsic_ref = other_intrinsic_ref,
            .supported_protocol_labels = &.{"approval-dual"},
            .supported_site_indexes = &.{ source_site_index, closure_dual_first.index },
            .supported_protocol_op_fingerprints = &.{closure_dual_first.fingerprint},
        });
        const selected_port = DualClosure.WorldPort.init(.{
            .label = "selected-direct-world-port",
            .kind = .test_fixture,
            .effect_shape_ref = direct_shape.evidenceRef(),
            .exposed_intrinsic_ref = selected_intrinsic_ref,
            .supported_protocol_labels = &.{"approval-dual"},
            .supported_site_indexes = &.{source_site_index},
            .supported_protocol_op_fingerprints = &.{closure_dual_second.fingerprint},
        });
        const direct_graph = DualClosure.Graph.init("direct-host-world-port-graph", &.{}, &.{}, &.{});
        const direct_report = DualClosure.Report.init(.{
            .graph_fingerprint = direct_graph.fingerprint,
            .root_program_refs = &.{dual_source_ref},
            .effect_shape_count = 2,
            .world_port_refs = &.{ other_port.evidenceRef(), selected_port.evidenceRef() },
            .open_world_port_count = 2,
        });
        const direct_certificate = DualClosure.Certificate.init(direct_report, direct_graph, DualClosure.Policy.auditOnly(), &.{ other_plan.evidenceRef(), selected_plan.evidenceRef() });
        const direct_input = DualElaboration.Input{
            .closure_graph = direct_graph,
            .closure_report = direct_report,
            .closure_certificate = direct_certificate,
            .static_treaty_plans = &.{ other_plan, selected_plan },
            .source_program_ref = dual_source_ref,
            .world_ports = &.{ other_port, selected_port },
            .policy = DualElaboration.Policy.auditOnly(),
        };
        const Body = DualElaboration.FromResidual(direct_input, closure_dual_world_port_program, .{ .label = "direct-host-world-port-body" });
        break :blk Body.source_map.worldPortForResidualSite(closure_dual_second.index).?.eql(selected_port.evidenceRef());
    };
    try std.testing.expect(direct_host_world_port_selection_uses_intrinsic);

    const unknown_world_port_rejected = comptime blk: {
        @setEvalBranchQuota(200_000);
        const unknown_shape = Closure.EffectShape.init(.{
            .program_label = "unknown-world-port-source",
            .kind = .operation,
            .site_index = closure_approval_request.index,
            .protocol_label = "approval",
            .protocol_op_fingerprint = closure_approval_request.fingerprint,
        });
        const unknown_plan = Closure.StaticTreatyPlan.init(.{
            .label = "unknown-world-port-plan",
            .source_shape = unknown_shape,
            .selected_semantic_body = .unknown,
        });
        const unknown_port = Closure.WorldPort.init(.{
            .label = "unknown-world-port",
            .kind = .test_fixture,
            .effect_shape_ref = unknown_shape.evidenceRef(),
            .supported_protocol_labels = &.{"approval"},
            .supported_site_indexes = &.{closure_approval_request.index},
            .supported_protocol_op_fingerprints = &.{closure_approval_request.fingerprint},
        });
        const unknown_graph = Closure.Graph.init("unknown-world-port-graph", &.{}, &.{}, &.{});
        const unknown_report = Closure.Report.init(.{
            .graph_fingerprint = unknown_graph.fingerprint,
            .root_program_refs = &.{source_ref},
            .effect_shape_count = 1,
            .world_port_refs = &.{unknown_port.evidenceRef()},
            .open_world_port_count = 1,
        });
        const unknown_certificate = Closure.Certificate.init(unknown_report, unknown_graph, Closure.Policy.auditOnly(), &.{unknown_plan.evidenceRef()});
        const unknown_input = Elaboration.Input{
            .closure_graph = unknown_graph,
            .closure_report = unknown_report,
            .closure_certificate = unknown_certificate,
            .static_treaty_plans = &.{unknown_plan},
            .source_program_ref = source_ref,
            .world_ports = &.{unknown_port},
            .policy = Elaboration.Policy.auditOnly(),
        };
        unknown_input.validate() catch |err| {
            if (err != error.BoundaryElaborationBlocked) break :blk false;
        };
        unknown_input.validateResidualProgram(closure_source_program) catch |err|
            break :blk err == error.BoundaryElaborationBlocked;
        break :blk false;
    };
    try std.testing.expect(unknown_world_port_rejected);

    const world_port_blockers_mapped = comptime blk: {
        @setEvalBranchQuota(200_000);
        const world_shape = Closure.EffectShape.init(.{
            .program_label = "world-port-blocker-source",
            .kind = .operation,
            .site_index = closure_approval_request.index,
            .protocol_label = "approval",
            .protocol_op_fingerprint = closure_approval_request.fingerprint,
        });
        const world_port = Closure.WorldPort.init(.{
            .label = "blocked-planned-world-port",
            .kind = .test_fixture,
            .effect_shape_ref = world_shape.evidenceRef(),
            .supported_protocol_labels = &.{"approval"},
            .supported_site_indexes = &.{closure_approval_request.index},
            .supported_protocol_op_fingerprints = &.{closure_approval_request.fingerprint},
        });
        const blocked_shape_ref = Evidence.refFor(Evidence.domains.boundary_effect_shape, 0xE1D21B, .{ .label = "blocked.world", .site_index = 7 });
        const blocker = Evidence.boundaryClosureBlocker(.{
            .tag = .unsupported_shape_planning,
            .summary = "unsupported shape remains blocked while world port lowers another shape",
            .subject = blocked_shape_ref,
            .site_index = 7,
        });
        const world_graph = Closure.Graph.init("world-port-blocker-graph", &.{}, &.{}, &.{});
        const world_source_ref = source_ref;
        const world_report = Closure.Report.init(.{
            .graph_fingerprint = world_graph.fingerprint,
            .root_program_refs = &.{world_source_ref},
            .effect_shape_count = 2,
            .world_port_refs = &.{world_port.evidenceRef()},
            .open_world_port_count = 1,
            .blockers = &.{blocker},
        });
        const world_certificate = Closure.Certificate.init(world_report, world_graph, Closure.Policy.auditOnly(), &.{});
        const world_input = Elaboration.Input{
            .closure_graph = world_graph,
            .closure_report = world_report,
            .closure_certificate = world_certificate,
            .source_program_ref = world_source_ref,
            .world_ports = &.{world_port},
            .policy = Elaboration.Policy.auditOnly(),
        };
        const Body = Elaboration.FromResidual(world_input, closure_source_program, .{ .label = "world-port-blocker-body" });
        break :blk Body.source_map.entries.len == 2 and
            Body.source_map.entries[0].disposition == .world_port_lowered and
            Body.source_map.entries[1].disposition == .blocked and
            Body.effect_row.source_effect_shapes == 2 and
            Body.effect_row.world_ports == 1 and
            Body.effect_row.blockers == 1;
    };
    try std.testing.expect(world_port_blockers_mapped);

    const duplicate_world_ports_rejected = comptime blk: {
        @setEvalBranchQuota(200_000);
        const shape_ref = Evidence.refFor(Evidence.domains.boundary_effect_shape, 0xE1D20F, .{ .label = "approval.request" });
        const first_port = Closure.WorldPort.init(.{
            .label = "first-approval-world-port",
            .kind = .test_fixture,
            .effect_shape_ref = shape_ref,
        });
        const second_port = Closure.WorldPort.init(.{
            .label = "second-approval-world-port",
            .kind = .test_fixture,
            .effect_shape_ref = shape_ref,
        });
        const duplicate_ports = [_]Closure.WorldPort{ first_port, second_port };
        const duplicate_graph = Closure.Graph.init("duplicate-world-port-graph", &.{}, &.{}, &.{});
        const duplicate_source_ref = source_ref;
        const duplicate_report = Closure.Report.init(.{
            .graph_fingerprint = duplicate_graph.fingerprint,
            .root_program_refs = &.{duplicate_source_ref},
            .effect_shape_count = 2,
            .world_port_refs = &.{ first_port.evidenceRef(), second_port.evidenceRef() },
            .open_world_port_count = 2,
        });
        const duplicate_certificate = Closure.Certificate.init(duplicate_report, duplicate_graph, Closure.Policy.auditOnly(), &.{});
        const duplicate_input = Elaboration.Input{
            .closure_graph = duplicate_graph,
            .closure_report = duplicate_report,
            .closure_certificate = duplicate_certificate,
            .source_program_ref = duplicate_source_ref,
            .world_ports = duplicate_ports[0..],
            .policy = Elaboration.Policy.auditOnly(),
        };
        duplicate_input.validateResidualProgram(closure_source_program) catch |err| break :blk err == error.BoundaryElaborationResidualProgramMismatch;
        break :blk false;
    };
    try std.testing.expect(duplicate_world_ports_rejected);

    const broad_port_rejected = comptime blk: {
        @setEvalBranchQuota(200_000);
        const shape_ref = Evidence.refFor(Evidence.domains.boundary_effect_shape, 0xE1D207, .{ .label = "approval.request" });
        const broad_port = Closure.WorldPort.init(.{
            .label = "broad-approval-world-port",
            .kind = .test_fixture,
            .effect_shape_ref = shape_ref,
        });
        const broad_ports = [_]Closure.WorldPort{broad_port};
        const broad_graph = Closure.Graph.init("broad-world-port-graph", &.{}, &.{}, &.{});
        const broad_source_ref = source_ref;
        const broad_report = Closure.Report.init(.{
            .graph_fingerprint = broad_graph.fingerprint,
            .root_program_refs = &.{broad_source_ref},
            .world_port_refs = &.{broad_port.evidenceRef()},
            .open_world_port_count = 1,
        });
        const broad_certificate = Closure.Certificate.init(broad_report, broad_graph, Closure.Policy.auditOnly(), &.{});
        const broad_input = Elaboration.Input{
            .closure_graph = broad_graph,
            .closure_report = broad_report,
            .closure_certificate = broad_certificate,
            .source_program_ref = broad_source_ref,
            .world_ports = broad_ports[0..],
            .policy = Elaboration.Policy.auditOnly(),
        };
        broad_input.validateResidualProgram(closure_multi_yield_program) catch |err| break :blk err == error.BoundaryElaborationResidualProgramMismatch;
        break :blk false;
    };
    try std.testing.expect(broad_port_rejected);

    const pipeline_shape = Closure.EffectShape.init(.{
        .program_label = "pipeline-source",
        .kind = .operation,
        .site_index = 0,
        .protocol_label = "approval",
    });
    const pipeline_plan = Closure.StaticTreatyPlan.init(.{
        .label = "pipeline-route",
        .source_shape = pipeline_shape,
        .selected_semantic_body = .pipeline,
        .selected_provider_ref = provider_ref,
        .selected_provider_offer_ref = provider_ref,
        .selected_capability_ref = provider_ref,
    });
    const pipeline_report = Closure.Report.init(.{
        .graph_fingerprint = graph.fingerprint,
        .root_program_refs = &.{source_ref},
    });
    const pipeline_certificate = Closure.Certificate.init(pipeline_report, graph, Closure.Policy.auditOnly(), &.{pipeline_plan.evidenceRef()});
    var no_pipeline_policy = Elaboration.Policy.auditOnly();
    no_pipeline_policy.allow_pipeline_adapters = false;
    const no_pipeline_input = Elaboration.Input{
        .closure_graph = graph,
        .closure_report = pipeline_report,
        .closure_certificate = pipeline_certificate,
        .static_treaty_plans = &.{pipeline_plan},
        .source_program_ref = source_ref,
        .policy = no_pipeline_policy,
    };
    try std.testing.expectEqual(error.BoundaryElaborationBlocked, no_pipeline_input.validate());

    var pipeline_policy = Elaboration.Policy.auditOnly();
    pipeline_policy.require_program_backed_providers_for_internal_routes = false;
    const missing_pipeline_proof_input = Elaboration.Input{
        .closure_graph = graph,
        .closure_report = pipeline_report,
        .closure_certificate = pipeline_certificate,
        .static_treaty_plans = &.{pipeline_plan},
        .source_program_ref = source_ref,
        .policy = pipeline_policy,
    };
    try std.testing.expectEqual(error.BoundaryElaborationBlocked, missing_pipeline_proof_input.validate());

    const morphism_ref = Evidence.refFor(Evidence.domains.morphism_offer, 0xE1D209, .{ .label = "pipeline-morphism" });
    const pipeline_ref = Evidence.refFor(Evidence.domains.pipeline, 0xE1D20A, .{ .label = "pipeline-proof" });
    const pipeline_dependencies = [_]Evidence.Dependency{
        .{ .role = .morphism, .ref = morphism_ref },
        .{ .role = .pipeline, .ref = pipeline_ref },
    };
    const proved_pipeline_plan = Closure.StaticTreatyPlan.init(.{
        .label = "pipeline-route",
        .source_shape = pipeline_shape,
        .selected_semantic_body = .pipeline,
        .selected_morphism_ref = morphism_ref,
        .selected_morphism_semantic_body = .pipeline,
        .selected_provider_ref = provider_ref,
        .selected_provider_offer_ref = provider_ref,
        .selected_capability_ref = provider_ref,
        .dependencies = pipeline_dependencies[0..],
    });
    const proved_pipeline_certificate = Closure.Certificate.init(pipeline_report, graph, Closure.Policy.auditOnly(), &.{proved_pipeline_plan.evidenceRef()});
    const proved_pipeline_input = Elaboration.Input{
        .closure_graph = graph,
        .closure_report = pipeline_report,
        .closure_certificate = proved_pipeline_certificate,
        .static_treaty_plans = &.{proved_pipeline_plan},
        .source_program_ref = source_ref,
        .morphism_offer_refs = &.{morphism_ref},
        .pipeline_adapter_refs = &.{pipeline_ref},
        .policy = pipeline_policy,
    };
    try proved_pipeline_input.validate();
    const wrong_pipeline_ref = Evidence.refFor(Evidence.domains.pipeline, 0xE1D20A + 1, .{ .label = "wrong-pipeline-proof" });
    const wrong_pipeline_input = Elaboration.Input{
        .closure_graph = graph,
        .closure_report = pipeline_report,
        .closure_certificate = proved_pipeline_certificate,
        .static_treaty_plans = &.{proved_pipeline_plan},
        .source_program_ref = source_ref,
        .morphism_offer_refs = &.{morphism_ref},
        .pipeline_adapter_refs = &.{wrong_pipeline_ref},
        .policy = pipeline_policy,
    };
    try std.testing.expectEqual(error.BoundaryElaborationBlocked, wrong_pipeline_input.validate());
    const wrong_morphism_ref = Evidence.refFor(Evidence.domains.morphism_offer, 0xE1D209 + 1, .{ .label = "wrong-pipeline-morphism" });
    const wrong_morphism_input = Elaboration.Input{
        .closure_graph = graph,
        .closure_report = pipeline_report,
        .closure_certificate = proved_pipeline_certificate,
        .static_treaty_plans = &.{proved_pipeline_plan},
        .source_program_ref = source_ref,
        .morphism_offer_refs = &.{wrong_morphism_ref},
        .pipeline_adapter_refs = &.{pipeline_ref},
        .policy = pipeline_policy,
    };
    try std.testing.expectEqual(error.BoundaryElaborationBlocked, wrong_morphism_input.validate());
    const pipeline_residual_accepted = comptime blk: {
        @setEvalBranchQuota(6_000_000);
        const ct_shape = Closure.EffectShape.init(.{
            .program_label = "pipeline-source",
            .kind = .operation,
            .site_index = 0,
            .protocol_label = "approval",
        });
        const ct_morphism_ref = Evidence.refFor(Evidence.domains.morphism_offer, 0xE1D20B, .{ .label = "ct-pipeline-morphism" });
        const ct_pipeline_ref = Evidence.refFor(Evidence.domains.pipeline, 0xE1D20C, .{ .label = "ct-pipeline-proof" });
        const ct_provider_ref = Evidence.refFor(Evidence.domains.program_plan, 0xE1D20D, .{ .label = "ct-provider" });
        const ct_source_ref = source_ref;
        const ct_dependencies = [_]Evidence.Dependency{
            .{ .role = .morphism, .ref = ct_morphism_ref },
            .{ .role = .pipeline, .ref = ct_pipeline_ref },
            .{ .role = .residual_program, .ref = ct_source_ref },
        };
        const ct_plan = Closure.StaticTreatyPlan.init(.{
            .label = "ct-pipeline-route",
            .source_shape = ct_shape,
            .selected_semantic_body = .pipeline,
            .selected_morphism_ref = ct_morphism_ref,
            .selected_morphism_semantic_body = .pipeline,
            .selected_provider_ref = ct_provider_ref,
            .selected_provider_offer_ref = ct_provider_ref,
            .selected_capability_ref = ct_provider_ref,
            .dependencies = ct_dependencies[0..],
        });
        const ct_graph = Closure.Graph.init("ct-pipeline-graph", &.{}, &.{}, &.{});
        const ct_report = Closure.Report.init(.{
            .graph_fingerprint = ct_graph.fingerprint,
            .root_program_refs = &.{ct_source_ref},
            .effect_shape_count = 1,
            .closed_effect_shape_count = 1,
            .residualized_pipeline_route_count = 1,
        });
        const ct_certificate = Closure.Certificate.init(ct_report, ct_graph, Closure.Policy.auditOnly(), &.{ct_plan.evidenceRef()});
        var ct_policy = Elaboration.Policy.auditOnly();
        ct_policy.require_program_backed_providers_for_internal_routes = false;
        const ct_input = Elaboration.Input{
            .closure_graph = ct_graph,
            .closure_report = ct_report,
            .closure_certificate = ct_certificate,
            .static_treaty_plans = &.{ct_plan},
            .source_program_ref = ct_source_ref,
            .policy = ct_policy,
        };
        const missing_residual_deps = [_]Evidence.Dependency{
            .{ .role = .morphism, .ref = ct_morphism_ref },
            .{ .role = .pipeline, .ref = ct_pipeline_ref },
        };
        const missing_residual_plan = Closure.StaticTreatyPlan.init(.{
            .label = "ct-pipeline-route-missing-residual",
            .source_shape = ct_shape,
            .selected_semantic_body = .pipeline,
            .selected_morphism_ref = ct_morphism_ref,
            .selected_morphism_semantic_body = .pipeline,
            .selected_provider_ref = ct_provider_ref,
            .selected_provider_offer_ref = ct_provider_ref,
            .selected_capability_ref = ct_provider_ref,
            .dependencies = missing_residual_deps[0..],
        });
        const missing_residual_cert = Closure.Certificate.init(ct_report, ct_graph, Closure.Policy.auditOnly(), &.{missing_residual_plan.evidenceRef()});
        const missing_residual_input = Elaboration.Input{
            .closure_graph = ct_graph,
            .closure_report = ct_report,
            .closure_certificate = missing_residual_cert,
            .static_treaty_plans = &.{missing_residual_plan},
            .source_program_ref = ct_source_ref,
            .policy = ct_policy,
        };
        const missing_residual_rejected = reject: {
            missing_residual_input.validateResidualProgram(Program) catch |err|
                break :reject err == error.BoundaryElaborationResidualProgramMismatch;
            break :reject false;
        };
        if (!missing_residual_rejected) break :blk false;
        const Body = Elaboration.FromResidual(ct_input, Program, .{ .label = "ct-pipeline-body" });
        break :blk Body.source_map.entries.len == 1 and
            Body.source_map.entries[0].disposition == .pipeline_adapter and
            Body.effect_row.pipeline_routes == 1;
    };
    try std.testing.expect(pipeline_residual_accepted);

    const residual_route_count_split = comptime blk: {
        @setEvalBranchQuota(6_000_000);
        const ct_shape = Closure.EffectShape.init(.{
            .program_label = "residualized-source",
            .kind = .operation,
            .site_index = 0,
            .protocol_label = "approval",
        });
        const ct_morphism_ref = Evidence.refFor(Evidence.domains.morphism_offer, 0xE1D21B, .{ .label = "ct-residualized-morphism" });
        const ct_provider_ref = Evidence.refFor(Evidence.domains.program_plan, 0xE1D21C, .{ .label = "ct-residualized-provider" });
        const ct_source_ref = source_ref;
        const ct_residual_ref = ct_source_ref;
        const ct_dependencies = [_]Evidence.Dependency{
            .{ .role = .morphism, .ref = ct_morphism_ref },
            .{ .role = .residual_program, .ref = ct_residual_ref },
        };
        const ct_plan = Closure.StaticTreatyPlan.init(.{
            .label = "ct-residualized-route",
            .source_shape = ct_shape,
            .selected_semantic_body = .residualized_program,
            .selected_morphism_ref = ct_morphism_ref,
            .selected_morphism_semantic_body = .residualized_program,
            .selected_provider_ref = ct_provider_ref,
            .selected_provider_offer_ref = ct_provider_ref,
            .selected_capability_ref = ct_provider_ref,
            .dependencies = ct_dependencies[0..],
        });
        const ct_graph = Closure.Graph.init("ct-residualized-graph", &.{}, &.{}, &.{});
        const ct_report = Closure.Report.init(.{
            .graph_fingerprint = ct_graph.fingerprint,
            .root_program_refs = &.{ct_source_ref},
            .effect_shape_count = 1,
            .closed_effect_shape_count = 1,
            .residualized_pipeline_route_count = 1,
        });
        const ct_certificate = Closure.Certificate.init(ct_report, ct_graph, Closure.Policy.auditOnly(), &.{ct_plan.evidenceRef()});
        var ct_policy = Elaboration.Policy.auditOnly();
        ct_policy.require_program_backed_providers_for_internal_routes = false;
        const ct_input = Elaboration.Input{
            .closure_graph = ct_graph,
            .closure_report = ct_report,
            .closure_certificate = ct_certificate,
            .static_treaty_plans = &.{ct_plan},
            .source_program_ref = ct_source_ref,
            .policy = ct_policy,
        };
        const Body = Elaboration.FromResidual(ct_input, Program, .{ .label = "ct-residualized-body" });
        break :blk Body.source_map.entries[0].disposition == .residualized and
            Body.effect_row.residualized_routes == 1 and
            Body.effect_row.pipeline_routes == 0 and
            Body.certificate.summary_counts.pipeline_routes_elaborated == 0;
    };
    try std.testing.expect(residual_route_count_split);

    const host_provider_pipeline = comptime blk: {
        @setEvalBranchQuota(3_000_000);
        const ct_shape = Closure.EffectShape.init(.{
            .program_label = "host-provider-pipeline-source",
            .kind = .operation,
            .site_index = closure_approval_request.index,
            .protocol_label = "approval",
            .protocol_op_fingerprint = closure_approval_request.fingerprint,
        });
        const intrinsic_ref = Evidence.refFor(Evidence.domains.host_intrinsic, 0xE1D24C, .{
            .label = "host-provider-pipeline-intrinsic",
            .kind_tag = @tagName(Evidence.HostIntrinsic.Kind.provider_function),
        });
        const ct_provider_ref = Evidence.refFor(Evidence.domains.provider_manifest, 0xE1D250, .{ .label = "host-provider-pipeline-provider" });
        const ct_morphism_ref = Evidence.refFor(Evidence.domains.morphism_offer, 0xE1D24D, .{ .label = "host-provider-pipeline-morphism" });
        const ct_pipeline_ref = Evidence.refFor(Evidence.domains.pipeline, 0xE1D24E, .{ .label = "host-provider-pipeline-proof" });
        const ct_dependencies = [_]Evidence.Dependency{
            .{ .role = .morphism, .ref = ct_morphism_ref },
            .{ .role = .pipeline, .ref = ct_pipeline_ref },
        };
        const ct_plan = Closure.StaticTreatyPlan.init(.{
            .label = "host-provider-pipeline-route",
            .source_shape = ct_shape,
            .selected_semantic_body = .host_intrinsic,
            .selected_intrinsic_ref = intrinsic_ref,
            .host_intrinsic = true,
            .selected_morphism_ref = ct_morphism_ref,
            .selected_morphism_semantic_body = .pipeline,
            .selected_provider_ref = ct_provider_ref,
            .selected_provider_offer_ref = ct_provider_ref,
            .selected_capability_ref = ct_provider_ref,
            .dependencies = ct_dependencies[0..],
        });
        const ct_port = Closure.WorldPort.init(.{
            .label = "unused-host-provider-world-port",
            .kind = .test_fixture,
            .effect_shape_ref = ct_shape.evidenceRef(),
            .exposed_intrinsic_ref = intrinsic_ref,
            .supported_protocol_labels = &.{"approval"},
            .supported_site_indexes = &.{closure_approval_request.index},
            .supported_protocol_op_fingerprints = &.{closure_approval_request.fingerprint},
        });
        const ct_graph = Closure.Graph.init("host-provider-pipeline-graph", &.{}, &.{}, &.{});
        const ct_report = Closure.Report.init(.{
            .graph_fingerprint = ct_graph.fingerprint,
            .root_program_refs = &.{source_ref},
            .effect_shape_count = 1,
            .closed_effect_shape_count = 1,
            .residualized_pipeline_route_count = 1,
            .world_port_refs = &.{ct_port.evidenceRef()},
            .open_world_port_count = 1,
        });
        var ct_policy = Elaboration.Policy.auditOnly();
        ct_policy.require_program_backed_providers_for_internal_routes = false;
        const lowered_entries = [_]Elaboration.SourceMap.Entry{.{
            .source_ref = ct_shape.evidenceRef(),
            .residual_ref = source_ref,
            .source_site_index = closure_approval_request.index,
            .residual_site_index = closure_approval_request.index,
            .static_treaty_plan_ref = ct_plan.evidenceRef(),
            .world_port_ref = ct_port.evidenceRef(),
            .disposition = .world_port_lowered,
            .label = "forged-host-provider-pipeline-world-port",
        }};
        const lowered_map = Elaboration.SourceMap.init("forged-host-provider-pipeline-map", lowered_entries[0..], &.{});
        const lowered_trace_entries = [_]Elaboration.TraceMap.Entry{.{
            .source_ref = ct_shape.evidenceRef(),
            .residual_ref = source_ref,
            .trace_label = "forged-host-provider-pipeline-world-port",
        }};
        const lowered_trace = Elaboration.TraceMap.init("forged-host-provider-pipeline-trace", lowered_trace_entries[0..]);
        const lowered_row = Elaboration.EffectRow.init(.{
            .label = "forged-host-provider-pipeline-row",
            .source_program_ref = source_ref,
            .residual_program_ref = source_ref,
            .normal_form = .world_ports_only,
            .source_effect_shapes = 1,
            .world_ports = 1,
            .residual_world_ports = 1,
        });
        const lowered_normal = Elaboration.NormalForm.init("forged-host-provider-pipeline-normal", .world_ports_only, ct_report.evidenceRef(), lowered_row.evidenceRef(), 0);
        const lowered_cert = Elaboration.Certificate.init(.{
            .elaborated_program_label = "forged-host-provider-pipeline",
            .source_program_ref = source_ref,
            .residual_program_ref = source_ref,
            .closure_certificate_ref = ct_report.evidenceRef(),
            .closure_graph_ref = ct_graph.evidenceRef(),
            .closure_report_ref = ct_report.evidenceRef(),
            .source_map_ref = lowered_map.evidenceRef(),
            .effect_row_ref = lowered_row.evidenceRef(),
            .trace_map_ref = lowered_trace.evidenceRef(),
            .normal_form_ref = lowered_normal.evidenceRef(),
            .policy = ct_policy,
            .normal_form = .world_ports_only,
            .selected_static_treaty_plan_refs = &.{ct_plan.evidenceRef()},
            .world_port_refs = &.{ct_port.evidenceRef()},
            .residual_world_port_refs = &.{ct_port.evidenceRef()},
            .summary_counts = .{
                .root_effect_shapes = 1,
                .world_ports_emitted = 1,
            },
        });
        lowered_cert.check(ct_policy, ct_graph.evidenceRef(), ct_report.evidenceRef(), ct_report.evidenceRef(), lowered_map, lowered_row, lowered_trace, lowered_normal, &.{ct_plan}, &.{ct_port}) catch |err| break :blk err == error.BoundaryElaborationCertificateMismatch;
        break :blk false;
    };
    try std.testing.expect(host_provider_pipeline);

    const dynamic_mapper_blocked = comptime blk: {
        @setEvalBranchQuota(200_000);
        const dynamic_ref = Evidence.refFor(Evidence.domains.host_intrinsic, 0xE1D24F, .{
            .label = "dynamic-world-mapper",
            .kind_tag = @tagName(Evidence.HostIntrinsic.Kind.dynamic_morphism_mapper),
        });
        const dynamic_shape = Closure.EffectShape.init(.{
            .program_label = "dynamic-world-source",
            .kind = .operation,
            .site_index = closure_approval_request.index,
            .protocol_label = "approval",
            .protocol_op_fingerprint = closure_approval_request.fingerprint,
        });
        const dynamic_plan = Closure.StaticTreatyPlan.init(.{
            .label = "dynamic-world-route",
            .source_shape = dynamic_shape,
            .selected_semantic_body = .host_intrinsic,
            .selected_intrinsic_ref = dynamic_ref,
            .host_intrinsic = true,
        });
        const dynamic_port = Closure.WorldPort.init(.{
            .label = "dynamic-world-port",
            .kind = .test_fixture,
            .effect_shape_ref = dynamic_shape.evidenceRef(),
            .exposed_intrinsic_ref = dynamic_ref,
            .supported_protocol_labels = &.{"approval"},
            .supported_site_indexes = &.{closure_approval_request.index},
            .supported_protocol_op_fingerprints = &.{closure_approval_request.fingerprint},
        });
        const dynamic_graph = Closure.Graph.init("dynamic-world-graph", &.{}, &.{}, &.{});
        const dynamic_report = Closure.Report.init(.{
            .graph_fingerprint = dynamic_graph.fingerprint,
            .root_program_refs = &.{source_ref},
            .effect_shape_count = 1,
            .world_port_refs = &.{dynamic_port.evidenceRef()},
            .open_world_port_count = 1,
        });
        var dynamic_policy = Elaboration.Policy.worldBoundary();
        dynamic_policy.require_certificate_checked = false;
        dynamic_policy.require_checked_closure_certificate = false;
        const dynamic_certificate = Closure.Certificate.init(dynamic_report, dynamic_graph, dynamic_policy.closure_policy, &.{dynamic_plan.evidenceRef()});
        const dynamic_input = Elaboration.Input{
            .closure_graph = dynamic_graph,
            .closure_report = dynamic_report,
            .closure_certificate = dynamic_certificate,
            .static_treaty_plans = &.{dynamic_plan},
            .source_program_ref = source_ref,
            .world_ports = &.{dynamic_port},
            .policy = dynamic_policy,
        };
        dynamic_input.validate() catch |err| break :blk err == error.BoundaryElaborationBlocked;
        break :blk false;
    };
    try std.testing.expect(dynamic_mapper_blocked);

    var program_backed_required_policy = pipeline_policy;
    program_backed_required_policy.require_program_backed_providers_for_internal_routes = true;
    const program_backed_required_input = Elaboration.Input{
        .closure_graph = graph,
        .closure_report = pipeline_report,
        .closure_certificate = proved_pipeline_certificate,
        .static_treaty_plans = &.{proved_pipeline_plan},
        .source_program_ref = source_ref,
        .policy = program_backed_required_policy,
    };
    try std.testing.expectEqual(error.BoundaryElaborationBlocked, program_backed_required_input.validate());
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
    try std.testing.expect(world_plan_policy.allowsHostIntrinsicRef(offer_intrinsic_ref));
    var nested_intrinsic_reject_policy = world_plan_policy;
    nested_intrinsic_reject_policy.defunctionalization_policy.allow_host_intrinsics = false;
    try std.testing.expect(!nested_intrinsic_reject_policy.allowsHostIntrinsicRef(offer_intrinsic_ref));
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
    var missing_authority_plan = plan;
    missing_authority_plan.selected_capability_ref = null;
    missing_authority_plan.fingerprint = missing_authority_plan.computeFingerprint();
    try std.testing.expect(!missing_authority_plan.closedUnderPolicy(world_plan_policy));
    var program_required_static_policy = world_plan_policy;
    program_required_static_policy.require_program_backed_providers = true;
    try std.testing.expect(!plan.closedUnderPolicy(program_required_static_policy));
    const static_plan = Program.Exchange.TreatyResolver.planStatic(.{
        .shape = shape,
        .manifest = manifest,
        .provider_manifests = &.{provider},
        .provider_offers = &.{offer},
        .capabilities = &.{capability},
    });
    try std.testing.expectEqual(Program.Exchange.TreatyResolver.StaticStatus.static_treaty, static_plan.status);
    try std.testing.expectEqual(offer_intrinsic_ref.fingerprint, static_plan.provider_intrinsic_ref.?.fingerprint);
    const max_zero_static_treaty_plan = Program.Exchange.TreatyResolver.planStatic(.{
        .shape = shape,
        .manifest = manifest,
        .provider_manifests = &.{provider},
        .provider_offers = &.{offer},
        .capabilities = &.{capability},
        .treaty_policy = .{
            .defunctionalization_policy = .{
                .maximum_intrinsic_count = 0,
            },
        },
    });
    try std.testing.expectEqual(Program.Exchange.TreatyResolver.StaticStatus.blocked, max_zero_static_treaty_plan.status);
    try std.testing.expectEqualStrings("treaty_policy_incompatible", max_zero_static_treaty_plan.blockers.slice()[0].tag);
    try std.testing.expectEqual(@as(u64, 0), max_zero_static_treaty_plan.provider_fingerprint);
    const semantic_label_only_shape = Evidence.BoundaryEffectShape.init(.{
        .program_label = "evidence-test",
        .plan_label = "evidence-test-plan",
        .plan_hash = 1,
        .kind = .operation,
        .site_index = site_index,
        .site_fingerprint = protocol_op_fingerprint,
        .semantic_label = "approval",
        .name = "approve",
        .mode = "transform",
        .value_ref = Evidence.BoundaryValueRef.fromValueRef(payload_ref),
        .expected_resume_ref = Evidence.BoundaryValueRef.fromValueRef(response_ref),
        .protocol_op_fingerprint = protocol_op_fingerprint,
    });
    const semantic_label_only_static_plan = Program.Exchange.TreatyResolver.planStatic(.{
        .shape = semantic_label_only_shape,
        .manifest = manifest,
        .provider_manifests = &.{provider},
        .provider_offers = &.{offer},
        .capabilities = &.{capability},
    });
    try std.testing.expectEqual(Program.Exchange.TreatyResolver.StaticStatus.blocked, semantic_label_only_static_plan.status);
    try std.testing.expectEqualStrings("unsupported_shape_planning", semantic_label_only_static_plan.blockers.slice()[0].tag);
    var forged_provider_intrinsic_ref = static_plan.provider_intrinsic_ref.?;
    forged_provider_intrinsic_ref.fingerprint +%= 1;
    var forged_provider_intrinsic_plan = static_plan;
    forged_provider_intrinsic_plan.provider_intrinsic_ref = forged_provider_intrinsic_ref;
    forged_provider_intrinsic_plan.fingerprint = forged_provider_intrinsic_plan.computeFingerprint();
    try std.testing.expect(static_plan.fingerprint != forged_provider_intrinsic_plan.fingerprint);

    var stale_direct_shape = shape;
    stale_direct_shape.site_fingerprint = protocol_op_fingerprint +% 1;
    const stale_direct_plan = try Program.Exchange.TreatyResolver.planShape(.{
        .allocator = allocator,
        .shape = stale_direct_shape,
        .provider_manifests = &.{provider},
        .provider_offers = &.{offer},
        .capabilities = &.{capability},
        .policy = world_plan_policy,
    });
    defer allocator.free(stale_direct_plan.blockers);
    defer allocator.free(stale_direct_plan.dependencies);
    try std.testing.expect(!stale_direct_plan.closed());
    try std.testing.expectEqual(@as(usize, 1), stale_direct_plan.blockers.len);
    try std.testing.expectEqual(Evidence.BoundaryClosureBlockerTag.stale_effect_shape, stale_direct_plan.blockers[0].tag);
    try std.testing.expect(stale_direct_plan.selected_provider_offer_ref == null);
    const stale_public_static_plan = Program.Exchange.TreatyResolver.planStatic(.{
        .shape = stale_direct_shape,
        .manifest = manifest,
        .provider_manifests = &.{provider},
        .provider_offers = &.{offer},
        .capabilities = &.{capability},
    });
    try std.testing.expectEqual(Program.Exchange.TreatyResolver.StaticStatus.blocked, stale_public_static_plan.status);
    try std.testing.expectEqualStrings("stale_effect_shape", stale_public_static_plan.blockers.slice()[0].tag);
    try std.testing.expectEqual(@as(u64, 0), stale_public_static_plan.provider_fingerprint);

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
    try std.testing.expect(max_zero_closure_plan.selected_provider_offer_ref == null);
    try std.testing.expect(max_zero_closure_plan.selected_intrinsic_ref == null);
    var max_zero_closure_result = try Program.BoundaryClosure.analyze(allocator, .{
        .allocator = allocator,
        .root_shapes = &.{shape},
        .provider_manifests = &.{provider},
        .provider_offers = &.{offer},
        .capabilities = &.{capability},
        .policy = max_zero_closure_policy,
    });
    defer max_zero_closure_result.deinit();
    try std.testing.expectEqual(@as(usize, 0), max_zero_closure_result.report.host_intrinsic_count);
    try std.testing.expectError(
        error.BoundaryClosureNotClosed,
        max_zero_closure_result.certificate.check(max_zero_closure_result.graph, max_zero_closure_result.report, max_zero_closure_policy, max_zero_closure_result.static_treaty_plans),
    );

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
    const rejected_replay_plan = try Program.Exchange.TreatyResolver.planShape(.{
        .allocator = allocator,
        .shape = shape,
        .provider_manifests = &.{provider},
        .provider_offers = &.{offer},
        .capabilities = &.{capability},
        .treaty_policy = .{ .require_obligation_opening = true },
        .policy = world_plan_policy,
    });
    defer allocator.free(rejected_replay_plan.blockers);
    defer allocator.free(rejected_replay_plan.dependencies);
    try std.testing.expect(!rejected_replay_plan.closed());
    try std.testing.expect(rejected_replay_plan.selected_provider_offer_ref == null);
    try std.testing.expect(rejected_replay_plan.blockers.len != 0);
    try std.testing.expectEqual(Evidence.BoundaryClosureBlockerTag.treaty_policy_incompatible, rejected_replay_plan.blockers[0].tag);
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
    const capsule_shape = Evidence.BoundaryEffectShape.init(.{
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
        .max_capsule_image_bytes = 8,
    });
    const capsule_present_required_plan = try Program.Exchange.TreatyResolver.planShape(.{
        .allocator = allocator,
        .shape = capsule_shape,
        .provider_manifests = &.{provider},
        .provider_offers = &.{capsule_required_offer},
        .capabilities = &.{capability},
        .policy = capsule_required_policy,
    });
    defer allocator.free(capsule_present_required_plan.blockers);
    defer allocator.free(capsule_present_required_plan.dependencies);
    try std.testing.expect(capsule_present_required_plan.closed());
    try std.testing.expectEqual(capsule_required_offer.evidenceRef().fingerprint, capsule_present_required_plan.selected_provider_offer_ref.?.fingerprint);
    const static_capsule_present_required_plan = Program.Exchange.TreatyResolver.planStatic(.{
        .shape = capsule_shape,
        .manifest = manifest,
        .provider_manifests = &.{provider},
        .provider_offers = &.{capsule_required_offer},
        .capabilities = &.{capability},
    });
    try std.testing.expectEqual(Program.Exchange.TreatyResolver.StaticStatus.static_treaty, static_capsule_present_required_plan.status);
    const static_no_fallback_plan = Program.Exchange.TreatyResolver.planStatic(.{
        .shape = capsule_shape,
        .manifest = manifest,
        .provider_manifests = &.{provider},
        .provider_offers = &.{capsule_required_offer},
        .capabilities = &.{capability},
        .allow_provider_fallback = false,
    });
    try std.testing.expectEqual(Program.Exchange.TreatyResolver.StaticStatus.no_static_treaty, static_no_fallback_plan.status);
    const static_capsule_route_blocked_plan = Program.Exchange.TreatyResolver.planStatic(.{
        .shape = capsule_shape,
        .manifest = manifest,
        .provider_manifests = &.{provider},
        .provider_offers = &.{capsule_required_offer},
        .capabilities = &.{capability},
        .route_policy = .{ .allow_capsules = false },
    });
    try std.testing.expect(static_capsule_route_blocked_plan.status != Program.Exchange.TreatyResolver.StaticStatus.static_treaty);
    var capsule_forbidden_offer = try Program.Exchange.ProviderOffer.encode(allocator, .{
        .label = "approval-capsule-forbidden-offer",
        .provider_fingerprint = provider.provider_fingerprint,
        .manifest_fingerprint = manifest.fingerprint,
        .supported_protocol_labels = &.{"approval"},
        .supported_operation_sites = &.{site_index},
        .supported_protocol_op_fingerprints = &.{protocol_op_fingerprint},
        .accepted_payload_refs = &.{payload_ref},
        .produced_response_refs = &.{response_ref},
        .capsule_policy = .forbidden,
    });
    defer capsule_forbidden_offer.deinit();
    const capsule_present_forbidden_plan = try Program.Exchange.TreatyResolver.planShape(.{
        .allocator = allocator,
        .shape = capsule_shape,
        .provider_manifests = &.{provider},
        .provider_offers = &.{capsule_forbidden_offer},
        .capabilities = &.{capability},
        .policy = world_plan_policy,
    });
    defer allocator.free(capsule_present_forbidden_plan.blockers);
    defer allocator.free(capsule_present_forbidden_plan.dependencies);
    try std.testing.expect(!capsule_present_forbidden_plan.closed());
    try std.testing.expect(capsule_present_forbidden_plan.selected_provider_offer_ref == null);

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
    const capsule_treaty_present_plan = try Program.Exchange.TreatyResolver.planShape(.{
        .allocator = allocator,
        .shape = capsule_shape,
        .provider_manifests = &.{provider},
        .provider_offers = &.{capsule_required_offer},
        .capabilities = &.{capability},
        .treaty_policy = .{ .require_capsule_embedding = true },
        .policy = capsule_required_policy,
    });
    defer allocator.free(capsule_treaty_present_plan.blockers);
    defer allocator.free(capsule_treaty_present_plan.dependencies);
    try std.testing.expect(capsule_treaty_present_plan.closed());
    try std.testing.expectEqual(capsule_required_offer.evidenceRef().fingerprint, capsule_treaty_present_plan.selected_provider_offer_ref.?.fingerprint);

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
    try std.testing.expect(!audit_missing_value_plan.byte_size_runtime_guard_required);

    var limited_capability = try Program.Exchange.Capability.encode(allocator, .{
        .issuer_label = "limited-host",
        .provider_fingerprint = provider.provider_fingerprint,
        .manifest_fingerprint = manifest.fingerprint,
        .allowed_operation_sites = &.{site_index},
        .allowed_protocol_op_fingerprints = &.{protocol_op_fingerprint},
        .allowed_requirement_labels = &.{"approval"},
        .allowed_op_names = &.{"approve"},
        .allowed_response_refs = &.{response_ref},
        .max_response_bytes = 16,
    });
    defer limited_capability.deinit();
    const finite_limit_plan = try Program.Exchange.TreatyResolver.planShape(.{
        .allocator = allocator,
        .shape = shape,
        .provider_manifests = &.{provider},
        .provider_offers = &.{offer},
        .capabilities = &.{limited_capability},
        .policy = audit_plan_policy,
    });
    defer allocator.free(finite_limit_plan.blockers);
    defer allocator.free(finite_limit_plan.dependencies);
    try std.testing.expect(finite_limit_plan.closed());
    try std.testing.expect(!finite_limit_plan.runtime_request_value_validation_required);
    try std.testing.expect(finite_limit_plan.byte_size_runtime_guard_required);

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

    const unbound_operation_shape = Evidence.BoundaryEffectShape.init(.{
        .program_label = "evidence-test",
        .plan_label = "evidence-test-plan",
        .plan_hash = 1,
        .kind = .operation,
        .name = "approve",
        .mode = "transform",
        .value_ref = Evidence.BoundaryValueRef.fromValueRef(payload_ref),
        .expected_resume_ref = Evidence.BoundaryValueRef.fromValueRef(response_ref),
        .protocol_label = "approval",
    });
    const unbound_operation_plan = try Program.Exchange.TreatyResolver.planShape(.{
        .allocator = allocator,
        .shape = unbound_operation_shape,
        .provider_manifests = &.{provider},
        .provider_offers = &.{offer},
        .capabilities = &.{capability},
        .policy = world_plan_policy,
    });
    defer allocator.free(unbound_operation_plan.blockers);
    defer allocator.free(unbound_operation_plan.dependencies);
    try std.testing.expect(!unbound_operation_plan.closed());
    try std.testing.expect(unbound_operation_plan.selected_provider_offer_ref == null);
    var saw_unbound_shape = false;
    for (unbound_operation_plan.blockers) |blocker| {
        if (blocker.tag == .effect_shape_unhandled) saw_unbound_shape = true;
    }
    try std.testing.expect(saw_unbound_shape);

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
    var saw_narrow_capability_blocker = false;
    var saw_narrow_provider_blocker = false;
    for (narrow_capability_plan.blockers) |blocker| {
        if (blocker.tag == .no_capability_for_shape) saw_narrow_capability_blocker = true;
        if (blocker.tag == .no_provider_offer_for_shape) saw_narrow_provider_blocker = true;
    }
    try std.testing.expect(saw_narrow_capability_blocker);
    try std.testing.expect(!saw_narrow_provider_blocker);

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
    const narrow_route_plan = try Program.Exchange.TreatyResolver.planShape(.{
        .allocator = allocator,
        .shape = byte_bounded_shape,
        .provider_manifests = &.{provider},
        .provider_offers = &.{offer},
        .capabilities = &.{forged_capability},
        .route_policy = .{ .max_envelope_bytes = 63 },
        .policy = world_plan_policy,
    });
    defer allocator.free(narrow_route_plan.blockers);
    defer allocator.free(narrow_route_plan.dependencies);
    try std.testing.expect(!narrow_route_plan.closed());
    try std.testing.expect(narrow_route_plan.selected_provider_offer_ref == null);
    const wrong_site_route_plan = try Program.Exchange.TreatyResolver.planShape(.{
        .allocator = allocator,
        .shape = byte_bounded_shape,
        .provider_manifests = &.{provider},
        .provider_offers = &.{offer},
        .capabilities = &.{forged_capability},
        .route_policy = .{ .allowed_operation_sites = &.{site_index + 1} },
        .policy = world_plan_policy,
    });
    defer allocator.free(wrong_site_route_plan.blockers);
    defer allocator.free(wrong_site_route_plan.dependencies);
    try std.testing.expect(!wrong_site_route_plan.closed());
    try std.testing.expect(wrong_site_route_plan.selected_provider_offer_ref == null);

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
    least_authority_closure_policy.reject_runtime_guards = false;
    least_authority_closure_policy.allow_runtime_guards = true;
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
        .policy = least_authority_closure_policy,
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

    const overflowing_static_offers = [_]Program.Exchange.ProviderOffer{offer} ** 17;
    const overflowing_static_plan = Program.Exchange.TreatyResolver.planStatic(.{
        .shape = shape,
        .manifest = manifest,
        .provider_manifests = &.{},
        .provider_offers = overflowing_static_offers[0..],
        .capabilities = &.{capability},
    });
    try std.testing.expect(overflowing_static_plan.blockers.truncated);
    try std.testing.expectEqual(@as(usize, 16), overflowing_static_plan.blockers.slice().len);
    const overflowing_static_report = overflowing_static_plan.toEvidenceReport(&.{});
    try std.testing.expect(!overflowing_static_report.success);
    try std.testing.expect(overflowing_static_report.truncated);
    try std.testing.expect(overflowing_static_report.omitted_fingerprint != null);
    try std.testing.expect(overflowing_static_report.hasErrors());
    try std.testing.expectError(error.EvidenceReportHasErrors, overflowing_static_report.assertOk());

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
    const narrow_route_static_plan = Program.Exchange.TreatyResolver.planStatic(.{
        .shape = byte_bound_shape,
        .manifest = manifest,
        .provider_manifests = &.{provider},
        .provider_offers = &.{offer},
        .capabilities = &.{capability},
        .route_policy = .{ .max_envelope_bytes = 63 },
    });
    try std.testing.expect(narrow_route_static_plan.status != Program.Exchange.TreatyResolver.StaticStatus.static_treaty);
    const wrong_site_route_static_plan = Program.Exchange.TreatyResolver.planStatic(.{
        .shape = byte_bound_shape,
        .manifest = manifest,
        .provider_manifests = &.{provider},
        .provider_offers = &.{offer},
        .capabilities = &.{capability},
        .route_policy = .{ .allowed_operation_sites = &.{site_index + 1} },
    });
    try std.testing.expect(wrong_site_route_static_plan.status != Program.Exchange.TreatyResolver.StaticStatus.static_treaty);

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
    try std.testing.expect(wildcard_source_target_static_plan.status != Program.Exchange.TreatyResolver.StaticStatus.static_treaty);
    try std.testing.expectEqual(@as(usize, 0), wildcard_source_target_static_plan.candidate_count);
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
    try std.testing.expect(!wildcard_source_target_closure_plan.closed());
    try std.testing.expect(wildcard_source_target_closure_plan.selected_morphism_ref == null);
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
    try std.testing.expect(!wildcard_source_target_closure.report.closedExceptWorldPorts());
    try std.testing.expectEqual(@as(usize, 0), wildcard_source_target_closure.report.residualized_pipeline_route_count);
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
    try std.testing.expectEqual(Program.Exchange.TreatyResolver.StaticStatus.no_static_treaty, partial_offer_multi_target_static_plan.status);
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
    try std.testing.expectEqual(Program.Exchange.TreatyResolver.StaticStatus.blocked, partial_capability_multi_target_static_plan.status);
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
    try std.testing.expectEqual(Program.Exchange.TreatyResolver.StaticStatus.blocked, label_scoped_target_static_plan.status);
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
    const static_dynamic_morphism_plan = Program.Exchange.TreatyResolver.planStatic(.{
        .shape = shape,
        .manifest = manifest,
        .provider_manifests = &.{morphism_target_provider},
        .provider_offers = &.{morphism_target_offer},
        .morphism_offers = &.{dynamic_morphism_offer},
        .capabilities = &.{morphism_capability},
        .treaty_policy = .{ .allow_direct_handling = false },
    });
    try std.testing.expectEqual(Program.Exchange.TreatyResolver.StaticStatus.static_treaty, static_dynamic_morphism_plan.status);
    try std.testing.expectEqual(dynamic_morphism_intrinsic_ref.fingerprint, static_dynamic_morphism_plan.morphism_intrinsic_ref.?.fingerprint);
    const count_limited_static_morphism_plan = Program.Exchange.TreatyResolver.planStatic(.{
        .shape = shape,
        .manifest = manifest,
        .provider_manifests = &.{morphism_target_provider},
        .provider_offers = &.{morphism_target_offer},
        .morphism_offers = &.{dynamic_morphism_offer},
        .capabilities = &.{morphism_capability},
        .treaty_policy = .{
            .allow_direct_handling = false,
            .defunctionalization_policy = .{
                .allow_host_intrinsics = true,
                .maximum_intrinsic_count = 1,
            },
        },
    });
    try std.testing.expectEqual(Program.Exchange.TreatyResolver.StaticStatus.blocked, count_limited_static_morphism_plan.status);
    try std.testing.expectEqualStrings("treaty_policy_incompatible", count_limited_static_morphism_plan.blockers.slice()[0].tag);
    try std.testing.expect(count_limited_static_morphism_plan.morphism_intrinsic_ref == null);
    var forged_morphism_intrinsic_ref = dynamic_morphism_intrinsic_ref;
    forged_morphism_intrinsic_ref.fingerprint +%= 1;
    var forged_morphism_intrinsic_plan = static_dynamic_morphism_plan;
    forged_morphism_intrinsic_plan.morphism_intrinsic_ref = forged_morphism_intrinsic_ref;
    forged_morphism_intrinsic_plan.fingerprint = forged_morphism_intrinsic_plan.computeFingerprint();
    try std.testing.expect(static_dynamic_morphism_plan.fingerprint != forged_morphism_intrinsic_plan.fingerprint);
    const static_dynamic_disabled_plan = Program.Exchange.TreatyResolver.planStatic(.{
        .shape = shape,
        .manifest = manifest,
        .provider_manifests = &.{morphism_target_provider},
        .provider_offers = &.{morphism_target_offer},
        .morphism_offers = &.{dynamic_morphism_offer},
        .capabilities = &.{morphism_capability},
        .treaty_policy = .{ .allow_direct_handling = false },
        .allow_dynamic_morphism = false,
    });
    try std.testing.expectEqual(Program.Exchange.TreatyResolver.StaticStatus.blocked, static_dynamic_disabled_plan.status);
    const rejected_morphism_target_provider_static_plan = Program.Exchange.TreatyResolver.planStatic(.{
        .shape = shape,
        .manifest = manifest,
        .provider_manifests = &.{morphism_target_provider},
        .provider_offers = &.{morphism_target_offer},
        .morphism_offers = &.{morphism_offer},
        .capabilities = &.{morphism_capability},
        .treaty_policy = .{ .allow_direct_handling = false, .reject_intrinsic_provider = true },
    });
    try std.testing.expectEqual(Program.Exchange.TreatyResolver.StaticStatus.blocked, rejected_morphism_target_provider_static_plan.status);
    try std.testing.expectEqual(@as(usize, 0), rejected_morphism_target_provider_static_plan.candidate_count);
    const rejected_morphism_target_provider_plan = try Program.Exchange.TreatyResolver.planShape(.{
        .allocator = allocator,
        .shape = shape,
        .provider_manifests = &.{morphism_target_provider},
        .provider_offers = &.{morphism_target_offer},
        .morphism_offers = &.{morphism_offer},
        .capabilities = &.{morphism_capability},
        .treaty_policy = .{ .allow_direct_handling = false, .reject_intrinsic_provider = true },
        .policy = morphism_policy,
    });
    defer allocator.free(rejected_morphism_target_provider_plan.blockers);
    defer allocator.free(rejected_morphism_target_provider_plan.dependencies);
    try std.testing.expect(!rejected_morphism_target_provider_plan.closed());
    try std.testing.expect(rejected_morphism_target_provider_plan.selected_provider_offer_ref == null);
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
    try std.testing.expect(dynamic_morphism_result.static_treaty_plans[0].selected_morphism_intrinsic_ref.?.eql(dynamic_morphism_intrinsic_ref));
    var saw_dynamic_morphism_intrinsic = false;
    for (dynamic_morphism_result.report.host_intrinsic_refs) |ref| {
        if (ref.eql(dynamic_morphism_intrinsic_ref)) saw_dynamic_morphism_intrinsic = true;
    }
    try std.testing.expect(saw_dynamic_morphism_intrinsic);
    const forged_dynamic_morphism_intrinsic_ref = Evidence.refFor(Evidence.domains.host_intrinsic, dynamic_morphism_intrinsic_ref.fingerprint +% 1, .{
        .label = "forged-dynamic-morphism",
        .kind_tag = @tagName(Evidence.HostIntrinsic.Kind.host_tool),
    });
    const forged_dynamic_nodes = try allocator.dupe(Program.BoundaryClosure.Graph.Node, dynamic_morphism_result.graph.nodes);
    defer allocator.free(forged_dynamic_nodes);
    for (forged_dynamic_nodes) |*node| {
        if (node.ref.eql(dynamic_morphism_intrinsic_ref)) node.ref = forged_dynamic_morphism_intrinsic_ref;
    }
    const forged_dynamic_edges = try allocator.dupe(Program.BoundaryClosure.Graph.Edge, dynamic_morphism_result.graph.edges);
    defer allocator.free(forged_dynamic_edges);
    for (forged_dynamic_edges) |*edge| {
        if (edge.from.eql(dynamic_morphism_intrinsic_ref)) edge.from = forged_dynamic_morphism_intrinsic_ref;
        if (edge.to.eql(dynamic_morphism_intrinsic_ref)) edge.to = forged_dynamic_morphism_intrinsic_ref;
    }
    const forged_dynamic_graph = Program.BoundaryClosure.Graph.init("forged-dynamic-morphism-intrinsic", forged_dynamic_nodes, forged_dynamic_edges, &.{});
    const forged_dynamic_host_refs = [_]Evidence.Ref{ forged_dynamic_morphism_intrinsic_ref, morphism_target_intrinsic_ref };
    const forged_dynamic_intrinsics = [_]u64{ forged_dynamic_morphism_intrinsic_ref.fingerprint, morphism_target_intrinsic_ref.fingerprint };
    var forged_dynamic_policy = dynamic_morphism_policy;
    forged_dynamic_policy.allowed_host_intrinsic_fingerprints = forged_dynamic_intrinsics[0..];
    var forged_dynamic_report = dynamic_morphism_result.report;
    forged_dynamic_report.graph_fingerprint = forged_dynamic_graph.fingerprint;
    forged_dynamic_report.host_intrinsic_refs = forged_dynamic_host_refs[0..];
    forged_dynamic_report.policy_summary = forged_dynamic_policy.policySummary();
    forged_dynamic_report.report_fingerprint = forged_dynamic_report.computeFingerprint();
    const forged_dynamic_certificate = Evidence.BoundaryClosureCertificate.init(
        forged_dynamic_report,
        forged_dynamic_graph,
        forged_dynamic_policy,
        dynamic_morphism_result.plan_refs,
    );
    try std.testing.expectError(
        error.BoundaryClosureCertificateMismatch,
        forged_dynamic_certificate.check(forged_dynamic_graph, forged_dynamic_report, forged_dynamic_policy, dynamic_morphism_result.static_treaty_plans),
    );
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
    const return_source_only_morphism = Program.Exchange.MorphismOffer{
        .label = "return-source-only-static-morphism",
        .source_site_fingerprint = protocol_op_fingerprint,
        .source_protocol_op_fingerprint = protocol_op_fingerprint,
        .target_protocol_op_fingerprint = target_protocol_op_fingerprint,
        .pipeline_fingerprint = 0x515157,
        .source_response_refs = &.{morphism_target_response_ref},
    };
    const return_source_only_plan = try Program.Exchange.TreatyResolver.planShape(.{
        .allocator = allocator,
        .shape = choice_shape,
        .provider_manifests = &.{morphism_target_provider},
        .provider_offers = &.{resume_only_target_offer},
        .morphism_offers = &.{return_source_only_morphism},
        .capabilities = &.{resume_only_target_capability},
        .treaty_policy = .{ .allow_direct_handling = false },
        .policy = return_kind_morphism_policy,
    });
    defer allocator.free(return_source_only_plan.blockers);
    defer allocator.free(return_source_only_plan.dependencies);
    try std.testing.expect(!return_source_only_plan.closed());
    try std.testing.expect(return_source_only_plan.selected_morphism_ref == null);
    const return_source_only_static_plan = Program.Exchange.TreatyResolver.planStatic(.{
        .shape = choice_shape,
        .manifest = manifest,
        .provider_manifests = &.{morphism_target_provider},
        .provider_offers = &.{resume_only_target_offer},
        .morphism_offers = &.{return_source_only_morphism},
        .capabilities = &.{resume_only_target_capability},
        .treaty_policy = .{ .allow_direct_handling = false },
    });
    try std.testing.expect(return_source_only_static_plan.status != Program.Exchange.TreatyResolver.StaticStatus.static_treaty);
    try std.testing.expect(return_source_only_static_plan.provider_offer_ref == null);
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
    const morphism_target_shape_without_responses = Evidence.BoundaryEffectShape.init(.{
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
    });
    var selected_target_response_refs = [_]Evidence.BoundaryValueRef{.{ .codec = "" }} ** 3;
    selected_target_response_refs[0] = target_shape_response_refs[0];
    const selected_response_ref_plan = Evidence.BoundaryStaticTreatyPlan.init(.{
        .label = "approval-morphism-target-response-ref-plan",
        .source_shape = shape,
        .selected_morphism_target_shape = morphism_target_shape_without_responses,
        .selected_morphism_target_response_ref_count = 1,
        .selected_morphism_target_response_refs = selected_target_response_refs,
    });
    const selected_response_ref_witness = selected_response_ref_plan.morphismTargetShapeWitness().?;
    try std.testing.expectEqual(selected_response_ref_witness.computeFingerprint(), selected_response_ref_witness.fingerprint);
    try std.testing.expect(!selected_response_ref_witness.evidenceRef().eql(morphism_target_shape_without_responses.evidenceRef()));
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
    try target_world_port_result.certificate.check(target_world_port_result.graph, target_world_port_result.report, morphism_target_world_policy, target_world_port_result.static_treaty_plans);
    const dynamic_mapper_world_port = Program.BoundaryClosure.WorldPort.init(.{
        .label = "approval-dynamic-mapper-world-port",
        .kind = .host_tool,
        .effect_shape_ref = morphism_target_shape.evidenceRef(),
        .exposed_intrinsic_ref = dynamic_morphism_intrinsic_ref,
        .supported_protocol_labels = &.{"approval"},
        .supported_site_indexes = &.{site_index},
        .supported_protocol_op_fingerprints = &.{target_protocol_op_fingerprint},
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
    try dynamic_multi_port_result.certificate.check(dynamic_multi_port_result.graph, dynamic_multi_port_result.report, dynamic_multi_port_policy, dynamic_multi_port_result.static_treaty_plans);
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
    var zero_hop_closed_policy = morphism_policy;
    zero_hop_closed_policy.max_morphism_hops = 0;
    try std.testing.expect(!morphism_plan.closedUnderPolicy(zero_hop_closed_policy));

    const policy_intrinsic = Evidence.HostIntrinsic.init(.{
        .label = "policy-closure-host-intrinsic",
        .kind = .provider_function,
        .owner_subsystem = .provider_harness,
        .associated_provider_offer_ref = offer.evidenceRef(),
    });
    const policy_morphism_intrinsic = Evidence.HostIntrinsic.init(.{
        .label = "policy-closure-morphism-intrinsic",
        .kind = .dynamic_morphism_mapper,
        .owner_subsystem = .morphism,
        .associated_morphism_offer_ref = morphism_offer.evidenceRef(),
    });
    const request_value_dependent_plan = Evidence.BoundaryStaticTreatyPlan.init(.{
        .label = "request-value-dependent-plan",
        .source_shape = shape,
        .selected_provider_offer_ref = offer.evidenceRef(),
        .selected_provider_ref = provider.evidenceRef(),
        .selected_capability_ref = capability.evidenceRef(),
        .selected_semantic_body = .declarative,
        .runtime_request_value_validation_required = true,
        .byte_size_runtime_guard_required = false,
    });
    var request_value_policy = Evidence.BoundaryClosurePolicy.auditOnly();
    request_value_policy.reject_request_value_dependence = true;
    request_value_policy.reject_runtime_guards = false;
    request_value_policy.allow_runtime_guards = true;
    try std.testing.expect(!request_value_dependent_plan.closedUnderPolicy(request_value_policy));
    const kernel_primitive_plan = Evidence.BoundaryStaticTreatyPlan.init(.{
        .label = "kernel-primitive-plan",
        .source_shape = shape,
        .selected_provider_offer_ref = offer.evidenceRef(),
        .selected_provider_ref = provider.evidenceRef(),
        .selected_capability_ref = capability.evidenceRef(),
        .selected_semantic_body = .kernel_primitive,
        .runtime_request_value_validation_required = false,
        .byte_size_runtime_guard_required = false,
    });
    var no_kernel_policy = Evidence.BoundaryClosurePolicy.auditOnly();
    no_kernel_policy.allow_kernel_primitives = false;
    no_kernel_policy.defunctionalization_policy.allow_kernel_primitives = false;
    try std.testing.expect(!kernel_primitive_plan.closedUnderPolicy(no_kernel_policy));
    const over_intrinsic_cap_plan = Evidence.BoundaryStaticTreatyPlan.init(.{
        .label = "over-intrinsic-cap-plan",
        .source_shape = shape,
        .selected_provider_offer_ref = offer.evidenceRef(),
        .selected_provider_ref = provider.evidenceRef(),
        .selected_capability_ref = capability.evidenceRef(),
        .selected_morphism_ref = morphism_offer.evidenceRef(),
        .selected_morphism_semantic_body = .host_intrinsic,
        .selected_morphism_intrinsic_ref = policy_morphism_intrinsic.evidenceRef(),
        .selected_semantic_body = .host_intrinsic,
        .selected_intrinsic_ref = policy_intrinsic.evidenceRef(),
        .runtime_request_value_validation_required = false,
        .byte_size_runtime_guard_required = false,
    });
    var capped_intrinsic_policy = Evidence.BoundaryClosurePolicy.auditOnly();
    capped_intrinsic_policy.defunctionalization_policy.maximum_intrinsic_count = 1;
    try std.testing.expect(!over_intrinsic_cap_plan.closedUnderPolicy(capped_intrinsic_policy));
    try std.testing.expect(!over_intrinsic_cap_plan.closedUnderPolicy(Evidence.BoundaryClosurePolicy.strictStatic()));
    var missing_intrinsic_policy = Evidence.BoundaryClosurePolicy.worldBoundary();
    const only_provider_intrinsic = [_]u64{policy_intrinsic.fingerprint};
    missing_intrinsic_policy.allowed_host_intrinsic_fingerprints = only_provider_intrinsic[0..];
    missing_intrinsic_policy.defunctionalization_policy.allowed_intrinsic_fingerprints = only_provider_intrinsic[0..];
    try std.testing.expect(!over_intrinsic_cap_plan.closedUnderPolicy(missing_intrinsic_policy));
    var allowlisted_intrinsic_policy = Evidence.BoundaryClosurePolicy.worldBoundary();
    const selected_intrinsics = [_]u64{ policy_intrinsic.fingerprint, policy_morphism_intrinsic.fingerprint };
    allowlisted_intrinsic_policy.allowed_host_intrinsic_fingerprints = selected_intrinsics[0..];
    allowlisted_intrinsic_policy.defunctionalization_policy.allowed_intrinsic_fingerprints = selected_intrinsics[0..];
    try std.testing.expect(over_intrinsic_cap_plan.closedUnderPolicy(allowlisted_intrinsic_policy));

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
    try std.testing.expectEqual(Program.Exchange.TreatyResolver.StaticStatus.blocked, static_source_capability_morphism_plan.status);
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
    var ambiguous_result = try Program.BoundaryClosure.analyze(allocator, .{
        .allocator = allocator,
        .root_shapes = &.{shape},
        .provider_manifests = &.{provider},
        .provider_offers = &.{ offer, second_offer },
        .capabilities = &.{capability},
        .policy = ambiguity_policy,
    });
    defer ambiguous_result.deinit();
    try std.testing.expect(!ambiguous_result.report.closed());
    try std.testing.expectEqual(@as(usize, 0), ambiguous_result.report.intrinsic_route_count);
    try std.testing.expect(ambiguous_result.report.host_intrinsic_count != 0);
    try std.testing.expectEqual(
        error.BoundaryClosureNotClosed,
        ambiguous_result.certificate.check(ambiguous_result.graph, ambiguous_result.report, ambiguity_policy, ambiguous_result.static_treaty_plans),
    );
}

test "boundary closure optional static treaty plans do not close unplanned shapes" {
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
        strict_result.certificate.check(strict_result.graph, strict_result.report, Evidence.BoundaryClosurePolicy.strictStatic(), strict_result.static_treaty_plans),
    );
    const derived_strict_certificate = Evidence.BoundaryClosureCertificate.init(
        strict_result.report,
        strict_result.graph,
        Evidence.BoundaryClosurePolicy.strictStatic(),
        strict_result.plan_refs,
    );
    try std.testing.expectEqual(
        error.BoundaryClosureNotClosed,
        derived_strict_certificate.check(strict_result.graph, strict_result.report, Evidence.BoundaryClosurePolicy.strictStatic(), strict_result.static_treaty_plans),
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
    try shape_only_result.certificate.check(shape_only_result.graph, shape_only_result.report, shape_only_policy, shape_only_result.static_treaty_plans);

    var audit_shape_only_result = try Closure.analyze(allocator, .{
        .allocator = allocator,
        .root_shapes = &.{shape},
        .policy = Evidence.BoundaryClosurePolicy.auditOnly(),
        .world_ports = shape_only_ports[0..],
    });
    defer audit_shape_only_result.deinit();
    try audit_shape_only_result.assertClosedExceptWorldPorts();
    try std.testing.expectEqual(@as(usize, 1), audit_shape_only_result.report.open_world_port_count);
    try audit_shape_only_result.certificate.check(audit_shape_only_result.graph, audit_shape_only_result.report, Evidence.BoundaryClosurePolicy.auditOnly(), audit_shape_only_result.static_treaty_plans);

    var optional_policy = Evidence.BoundaryClosurePolicy.strictStatic();
    optional_policy.label = "optional_static";
    optional_policy.require_static_treaty_plans = false;
    var optional_result = try Closure.analyze(allocator, .{
        .allocator = allocator,
        .root_shapes = &.{shape},
        .policy = optional_policy,
    });
    defer optional_result.deinit();
    try std.testing.expectEqual(error.BoundaryClosureNotClosed, optional_result.assertClosed());
    try std.testing.expectEqual(@as(usize, 1), optional_result.report.effect_shape_count);
    try std.testing.expectEqual(@as(usize, 0), optional_result.report.closed_effect_shape_count);
    try std.testing.expectEqual(@as(usize, 0), optional_result.report.blocker_count);
    try std.testing.expectEqual(@as(usize, 0), optional_result.report.unknown_body_count);
    try std.testing.expectEqual(@as(usize, 1), optional_result.static_treaty_plans.len);
    try std.testing.expect(optional_result.static_treaty_plans[0].selected_provider_offer_ref == null);
    try std.testing.expect(!optional_result.static_treaty_plans[0].closedUnderPolicy(optional_policy));
    const optional_evidence_report = optional_result.report.toEvidenceReport();
    try std.testing.expect(!optional_evidence_report.success);
    try std.testing.expectError(error.EvidenceReportHasErrors, optional_evidence_report.assertOk());
    try std.testing.expectEqual(
        error.BoundaryClosureNotClosed,
        optional_result.certificate.check(optional_result.graph, optional_result.report, optional_policy, optional_result.static_treaty_plans),
    );
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
    try std.testing.expectEqual(@as(usize, 1), result.report.intrinsic_route_count);
    try std.testing.expectEqual(@as(usize, 1), result.static_treaty_plans.len);
    try std.testing.expectEqual(offer.evidenceRef().fingerprint, result.static_treaty_plans[0].selected_provider_offer_ref.?.fingerprint);
    try result.certificate.check(result.graph, result.report, closure_policy, result.static_treaty_plans);
    try std.testing.expect(Evidence.refForBoundaryClosureCertificate(result.certificate).eql(result.certificate.evidenceRef()));
    var stale_source_shape_plan = result.static_treaty_plans[0];
    stale_source_shape_plan.source_shape.name = "forged-stale-source-shape";
    try std.testing.expectEqual(result.static_treaty_plans[0].fingerprint, stale_source_shape_plan.fingerprint);
    try std.testing.expect(stale_source_shape_plan.source_shape.fingerprint != stale_source_shape_plan.source_shape.computeFingerprint());
    try std.testing.expectError(
        error.BoundaryClosureCertificateMismatch,
        result.certificate.check(result.graph, result.report, closure_policy, &.{stale_source_shape_plan}),
    );

    const audit_policy = Evidence.BoundaryClosurePolicy.auditOnly();
    var renamed_audit_policy = audit_policy;
    renamed_audit_policy.label = "custom-audit-label";
    var renamed_audit_result = try Closure.analyze(allocator, .{
        .allocator = allocator,
        .root_shapes = &.{shape},
        .provider_manifests = &.{provider},
        .provider_offers = &.{offer},
        .capabilities = &.{capability},
        .policy = renamed_audit_policy,
    });
    defer renamed_audit_result.deinit();
    try renamed_audit_result.certificate.check(renamed_audit_result.graph, renamed_audit_result.report, renamed_audit_policy, renamed_audit_result.static_treaty_plans);
    var duplicate_shape_result = try Closure.analyze(allocator, .{
        .allocator = allocator,
        .root_shapes = &.{ shape, shape },
        .provider_manifests = &.{provider},
        .provider_offers = &.{offer},
        .capabilities = &.{capability},
        .policy = audit_policy,
    });
    defer duplicate_shape_result.deinit();
    try std.testing.expectEqual(@as(usize, 1), duplicate_shape_result.report.effect_shape_count);
    try std.testing.expectEqual(@as(usize, 1), duplicate_shape_result.plan_refs.len);
    try std.testing.expectEqual(@as(usize, 1), duplicate_shape_result.report.blocker_count);
    try std.testing.expectEqualStrings("duplicate_effect_shape", duplicate_shape_result.report.blockers[0].tag);
    try duplicate_shape_result.certificate.check(duplicate_shape_result.graph, duplicate_shape_result.report, audit_policy, duplicate_shape_result.static_treaty_plans);

    var stale_shape = shape;
    stale_shape.name = "approve-tampered";
    try std.testing.expect(stale_shape.fingerprint != stale_shape.computeFingerprint());
    var stale_shape_result = try Closure.analyze(allocator, .{
        .allocator = allocator,
        .root_shapes = &.{stale_shape},
        .provider_manifests = &.{provider},
        .provider_offers = &.{offer},
        .capabilities = &.{capability},
        .policy = audit_policy,
    });
    defer stale_shape_result.deinit();
    try std.testing.expectEqual(@as(usize, 0), stale_shape_result.report.effect_shape_count);
    try std.testing.expectEqual(@as(usize, 0), stale_shape_result.plan_refs.len);
    try std.testing.expectEqual(@as(usize, 1), stale_shape_result.report.blocker_count);
    try std.testing.expectEqualStrings("stale_effect_shape", stale_shape_result.report.blockers[0].tag);
    try stale_shape_result.certificate.check(stale_shape_result.graph, stale_shape_result.report, audit_policy, stale_shape_result.static_treaty_plans);
    const stale_shape_root_ref = Evidence.refFor(Evidence.domains.program_plan, shape.plan_hash, .{ .label = shape.program_label });
    var stale_shape_root_result = try Closure.analyze(allocator, .{
        .allocator = allocator,
        .root_shapes = &.{stale_shape},
        .root_program_refs = &.{stale_shape_root_ref},
        .provider_manifests = &.{provider},
        .provider_offers = &.{offer},
        .capabilities = &.{capability},
        .policy = audit_policy,
    });
    defer stale_shape_root_result.deinit();
    var saw_stale_shape_root_missing = false;
    for (stale_shape_root_result.report.blockers) |blocker| {
        if (std.mem.eql(u8, blocker.tag, "root_program_missing") and blocker.subject != null and blocker.subject.?.eql(stale_shape_root_ref)) {
            saw_stale_shape_root_missing = true;
        }
    }
    try std.testing.expect(saw_stale_shape_root_missing);

    const shape_missing_op_selector = Evidence.BoundaryEffectShape.init(.{
        .program_label = "evidence-test",
        .plan_label = "evidence-test-plan-missing-op",
        .plan_hash = 11,
        .manifest_fingerprint = manifest.fingerprint,
        .kind = .operation,
        .site_index = site_index,
        .site_fingerprint = protocol_op_fingerprint,
        .name = "approve",
        .mode = "transform",
        .value_ref = Evidence.BoundaryValueRef.fromValueRef(payload_ref),
        .expected_resume_ref = Evidence.BoundaryValueRef.fromValueRef(response_ref),
        .protocol_label = "approval",
    });
    var missing_op_selector_result = try Closure.analyze(allocator, .{
        .allocator = allocator,
        .root_shapes = &.{shape_missing_op_selector},
        .provider_manifests = &.{provider},
        .provider_offers = &.{offer},
        .capabilities = &.{capability},
        .policy = closure_policy,
    });
    defer missing_op_selector_result.deinit();
    try std.testing.expect(!missing_op_selector_result.report.closed());
    try std.testing.expectEqual(@as(usize, 0), missing_op_selector_result.report.closed_effect_shape_count);

    const shape_missing_site_selector = Evidence.BoundaryEffectShape.init(.{
        .program_label = "evidence-test",
        .plan_label = "evidence-test-plan-missing-site",
        .plan_hash = 12,
        .manifest_fingerprint = manifest.fingerprint,
        .kind = .operation,
        .site_fingerprint = protocol_op_fingerprint,
        .name = "approve",
        .mode = "transform",
        .value_ref = Evidence.BoundaryValueRef.fromValueRef(payload_ref),
        .expected_resume_ref = Evidence.BoundaryValueRef.fromValueRef(response_ref),
        .protocol_label = "approval",
        .protocol_op_fingerprint = protocol_op_fingerprint,
    });
    var missing_site_selector_result = try Closure.analyze(allocator, .{
        .allocator = allocator,
        .root_shapes = &.{shape_missing_site_selector},
        .provider_manifests = &.{provider},
        .provider_offers = &.{offer},
        .capabilities = &.{capability},
        .policy = closure_policy,
    });
    defer missing_site_selector_result.deinit();
    try std.testing.expect(!missing_site_selector_result.report.closed());
    try std.testing.expectEqual(@as(usize, 0), missing_site_selector_result.report.closed_effect_shape_count);

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
    var provider_harness_ref_inputs = [_]Evidence.Ref{
        Evidence.refFor(Evidence.domains.provider_harness, provider.fingerprint, .{ .label = provider.label }),
    };
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
    try owned_ref_result.certificate.check(owned_ref_result.graph, owned_ref_result.report, closure_policy, owned_ref_result.static_treaty_plans);
    const mismatched_label_root_ref = Evidence.refFor(Evidence.domains.program_plan, shape.plan_hash, .{ .label = "mismatched-root-program" });
    var mismatched_label_root_result = try Closure.analyze(allocator, .{
        .allocator = allocator,
        .root_shapes = &.{shape},
        .root_program_refs = &.{mismatched_label_root_ref},
        .provider_manifests = &.{provider},
        .provider_offers = &.{offer},
        .capabilities = &.{capability},
        .policy = closure_policy,
    });
    defer mismatched_label_root_result.deinit();
    try std.testing.expect(!mismatched_label_root_result.report.closed());
    var saw_label_shape_blocker = false;
    var saw_label_root_blocker = false;
    for (mismatched_label_root_result.report.blockers) |blocker| {
        if (std.mem.eql(u8, blocker.tag, "root_program_missing") and blocker.subject != null) {
            if (blocker.subject.?.eql(shape.evidenceRef())) saw_label_shape_blocker = true;
            if (blocker.subject.?.eql(mismatched_label_root_ref)) saw_label_root_blocker = true;
        }
    }
    try std.testing.expect(saw_label_shape_blocker);
    try std.testing.expect(saw_label_root_blocker);
    for (mismatched_label_root_result.graph.edges) |edge| {
        try std.testing.expect(!(edge.kind == .root_yields and edge.from.eql(mismatched_label_root_ref) and edge.to.eql(shape.evidenceRef())));
    }
    const missing_hash_shape = Evidence.BoundaryEffectShape.init(.{
        .program_label = shape.program_label,
        .plan_label = shape.plan_label,
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
    const matching_label_root_ref = Evidence.refFor(Evidence.domains.program_plan, 0x515151, .{ .label = missing_hash_shape.program_label });
    var missing_hash_root_result = try Closure.analyze(allocator, .{
        .allocator = allocator,
        .root_shapes = &.{missing_hash_shape},
        .root_program_refs = &.{matching_label_root_ref},
        .provider_manifests = &.{provider},
        .provider_offers = &.{offer},
        .capabilities = &.{capability},
        .policy = closure_policy,
    });
    defer missing_hash_root_result.deinit();
    try std.testing.expect(!missing_hash_root_result.report.closed());
    var saw_missing_hash_root_blocker = false;
    for (missing_hash_root_result.report.blockers) |blocker| {
        if (std.mem.eql(u8, blocker.tag, "root_program_missing") and blocker.subject != null and blocker.subject.?.eql(missing_hash_shape.evidenceRef())) {
            saw_missing_hash_root_blocker = true;
        }
    }
    try std.testing.expect(saw_missing_hash_root_blocker);
    for (missing_hash_root_result.graph.edges) |edge| {
        try std.testing.expect(!(edge.kind == .root_yields and edge.from.eql(matching_label_root_ref) and edge.to.eql(missing_hash_shape.evidenceRef())));
    }
    var configured_root_policy = closure_policy;
    configured_root_policy.require_root_program_refs = true;
    var rootless_configured_result = try Closure.analyze(allocator, .{
        .allocator = allocator,
        .root_shapes = &.{shape},
        .provider_manifests = &.{provider},
        .provider_offers = &.{offer},
        .capabilities = &.{capability},
        .policy = configured_root_policy,
    });
    defer rootless_configured_result.deinit();
    try std.testing.expect(!rootless_configured_result.report.closed());
    var saw_rootless_blocker = false;
    for (rootless_configured_result.report.blockers) |blocker| {
        if (std.mem.eql(u8, blocker.tag, "root_program_missing") and blocker.subject != null and blocker.subject.?.eql(shape.evidenceRef())) {
            saw_rootless_blocker = true;
        }
    }
    try std.testing.expect(saw_rootless_blocker);
    try std.testing.expectError(
        error.BoundaryClosureCertificateMismatch,
        rootless_configured_result.certificate.check(rootless_configured_result.graph, rootless_configured_result.report, configured_root_policy, rootless_configured_result.static_treaty_plans),
    );
    var effect_free_root_yield_report = owned_ref_result.report;
    effect_free_root_yield_report.effect_free_root_refs = owned_ref_result.report.root_program_refs;
    effect_free_root_yield_report.report_fingerprint = effect_free_root_yield_report.computeFingerprint();
    const effect_free_root_yield_certificate = Evidence.BoundaryClosureCertificate.init(
        effect_free_root_yield_report,
        owned_ref_result.graph,
        closure_policy,
        owned_ref_result.plan_refs,
    );
    try std.testing.expectError(
        error.BoundaryClosureCertificateMismatch,
        effect_free_root_yield_certificate.check(owned_ref_result.graph, effect_free_root_yield_report, closure_policy, owned_ref_result.static_treaty_plans),
    );

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
        missing_root_shape_result.certificate.check(missing_root_shape_result.graph, missing_root_shape_result.report, closure_policy, missing_root_shape_result.static_treaty_plans),
    );

    const unrooted_effect_free_ref = Evidence.refFor(Evidence.domains.program_plan, 0xEFFEC7F2EF, .{ .label = "unrooted-effect-free-root" });
    var unrooted_effect_free_result = try Closure.analyze(allocator, .{
        .allocator = allocator,
        .root_program_refs = &.{effect_free_root_ref},
        .effect_free_root_refs = &.{ effect_free_root_ref, unrooted_effect_free_ref },
        .policy = closure_policy,
    });
    defer unrooted_effect_free_result.deinit();
    try std.testing.expectEqual(@as(usize, 1), unrooted_effect_free_result.report.blocker_count);
    try std.testing.expect(!unrooted_effect_free_result.report.closed());
    try std.testing.expectError(
        error.BoundaryClosureNotClosed,
        unrooted_effect_free_result.certificate.check(unrooted_effect_free_result.graph, unrooted_effect_free_result.report, closure_policy, unrooted_effect_free_result.static_treaty_plans),
    );

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
    try effect_free_root_result.certificate.check(effect_free_root_result.graph, effect_free_root_result.report, closure_policy, effect_free_root_result.static_treaty_plans);

    const conflicting_effect_free_root_ref = Evidence.refFor(Evidence.domains.program_plan, shape.plan_hash, .{ .label = shape.program_label });
    var conflicting_effect_free_root_result = try Closure.analyze(allocator, .{
        .allocator = allocator,
        .root_shapes = &.{shape},
        .root_program_refs = &.{conflicting_effect_free_root_ref},
        .effect_free_root_refs = &.{conflicting_effect_free_root_ref},
        .provider_manifests = &.{provider},
        .provider_offers = &.{offer},
        .capabilities = &.{capability},
        .policy = closure_policy,
    });
    defer conflicting_effect_free_root_result.deinit();
    try std.testing.expect(!conflicting_effect_free_root_result.report.closed());
    try std.testing.expectEqual(@as(usize, 0), conflicting_effect_free_root_result.report.effect_shape_count);
    try std.testing.expectEqual(@as(usize, 1), conflicting_effect_free_root_result.report.blocker_count);
    try std.testing.expectError(
        error.BoundaryClosureNotClosed,
        conflicting_effect_free_root_result.certificate.check(conflicting_effect_free_root_result.graph, conflicting_effect_free_root_result.report, closure_policy, conflicting_effect_free_root_result.static_treaty_plans),
    );

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
    try world_port_result.certificate.check(world_port_result.graph, world_port_result.report, world_port_only_policy, world_port_result.static_treaty_plans);

    var stale_world_port = Closure.WorldPort.init(.{
        .label = "stale-approval-world-port",
        .kind = .host_tool,
        .effect_shape_ref = shape_missing_op_selector.evidenceRef(),
        .exposed_intrinsic_ref = offer_intrinsic_ref,
        .supported_protocol_labels = &.{"other"},
        .supported_site_indexes = &.{site_index + 1},
        .supported_protocol_op_fingerprints = &.{protocol_op_fingerprint + 1},
    });
    const stale_world_port_allowed = [_]u64{stale_world_port.fingerprint};
    stale_world_port.effect_shape_ref = shape.evidenceRef();
    stale_world_port.supported_protocol_labels = &.{"approval"};
    stale_world_port.supported_site_indexes = &.{site_index};
    stale_world_port.supported_protocol_op_fingerprints = &.{protocol_op_fingerprint};
    try std.testing.expect(stale_world_port.fingerprint != stale_world_port.computeFingerprint());
    const stale_world_ports = [_]Closure.WorldPort{stale_world_port};
    var stale_world_port_policy = Evidence.BoundaryClosurePolicy.worldBoundary();
    stale_world_port_policy.allowed_world_port_fingerprints = stale_world_port_allowed[0..];
    stale_world_port_policy.reject_host_intrinsics = true;
    var stale_world_port_result = try Closure.analyze(allocator, .{
        .allocator = allocator,
        .root_shapes = &.{shape},
        .provider_manifests = &.{provider},
        .provider_offers = &.{offer},
        .capabilities = &.{capability},
        .policy = stale_world_port_policy,
        .world_ports = stale_world_ports[0..],
    });
    defer stale_world_port_result.deinit();
    try std.testing.expectEqual(@as(usize, 0), stale_world_port_result.report.open_world_port_count);
    var saw_stale_world_port_blocker = false;
    for (stale_world_port_result.report.blockers) |blocker| {
        if (std.mem.eql(u8, blocker.tag, "stale_world_port")) saw_stale_world_port_blocker = true;
    }
    try std.testing.expect(saw_stale_world_port_blocker);
    try std.testing.expect(!stale_world_port_result.report.closedExceptWorldPorts());
    try std.testing.expectError(
        error.BoundaryClosureNotClosed,
        stale_world_port_result.certificate.check(stale_world_port_result.graph, stale_world_port_result.report, stale_world_port_policy, stale_world_port_result.static_treaty_plans),
    );

    var selectorless_provider = try Program.Exchange.ProviderManifest.encode(allocator, .{
        .label = "selectorless-closure-provider",
        .supported_program_manifest_fingerprints = &.{manifest.fingerprint},
        .supported_protocol_labels = &.{"approval"},
    });
    defer selectorless_provider.deinit();
    var selectorless_offer = try Program.Exchange.ProviderOffer.encode(allocator, .{
        .label = "selectorless-closure-offer",
        .provider_fingerprint = selectorless_provider.provider_fingerprint,
        .manifest_fingerprint = manifest.fingerprint,
        .supported_protocol_labels = &.{"approval"},
        .accepted_payload_refs = &.{payload_ref},
        .produced_response_refs = &.{response_ref},
    });
    defer selectorless_offer.deinit();
    const selectorless_intrinsic_ref = selectorless_offer.hostIntrinsicRef() orelse return error.ExpectedIntrinsic;
    var selectorless_capability = try Program.Exchange.Capability.encode(allocator, .{
        .issuer_label = "selectorless-host",
        .provider_fingerprint = selectorless_provider.provider_fingerprint,
        .manifest_fingerprint = manifest.fingerprint,
        .allowed_response_refs = &.{response_ref},
    });
    defer selectorless_capability.deinit();
    const constrained_unbound_port = Closure.WorldPort.init(.{
        .label = "constrained-unbound-world-port",
        .kind = .host_tool,
        .exposed_intrinsic_ref = selectorless_intrinsic_ref,
        .supported_protocol_labels = &.{"approval"},
        .supported_site_indexes = &.{site_index},
        .supported_protocol_op_fingerprints = &.{protocol_op_fingerprint},
    });
    const constrained_unbound_ports = [_]Closure.WorldPort{constrained_unbound_port};
    var constrained_unbound_policy = Evidence.BoundaryClosurePolicy.worldBoundary();
    const constrained_unbound_allowed = [_]u64{constrained_unbound_port.fingerprint};
    constrained_unbound_policy.allowed_world_port_fingerprints = constrained_unbound_allowed[0..];
    constrained_unbound_policy.reject_host_intrinsics = true;
    const selectorless_shape = Evidence.BoundaryEffectShape.init(.{
        .program_label = "evidence-test",
        .plan_label = "evidence-test-selectorless-world",
        .plan_hash = 13,
        .manifest_fingerprint = manifest.fingerprint,
        .kind = .operation,
        .name = "approve",
        .mode = "transform",
        .value_ref = Evidence.BoundaryValueRef.fromValueRef(payload_ref),
        .expected_resume_ref = Evidence.BoundaryValueRef.fromValueRef(response_ref),
        .protocol_label = "approval",
    });
    var constrained_unbound_result = try Closure.analyze(allocator, .{
        .allocator = allocator,
        .root_shapes = &.{selectorless_shape},
        .provider_manifests = &.{selectorless_provider},
        .provider_offers = &.{selectorless_offer},
        .capabilities = &.{selectorless_capability},
        .policy = constrained_unbound_policy,
        .world_ports = constrained_unbound_ports[0..],
    });
    defer constrained_unbound_result.deinit();
    try std.testing.expect(!constrained_unbound_result.report.closedExceptWorldPorts());
    try std.testing.expectEqual(@as(usize, 0), constrained_unbound_result.report.open_world_port_count);

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
    try mixed_world_result.assertClosed();
    try std.testing.expectEqual(@as(usize, 2), mixed_world_result.report.effect_shape_count);
    try std.testing.expectEqual(@as(usize, 2), mixed_world_result.report.closed_effect_shape_count);
    try std.testing.expectEqual(@as(usize, 0), mixed_world_result.report.open_world_port_count);
    try mixed_world_result.certificate.check(mixed_world_result.graph, mixed_world_result.report, mixed_world_policy, mixed_world_result.static_treaty_plans);

    const stray_world_obligation_edges = try allocator.alloc(Closure.Graph.Edge, world_port_result.graph.edges.len + 1);
    defer allocator.free(stray_world_obligation_edges);
    @memcpy(stray_world_obligation_edges[0..world_port_result.graph.edges.len], world_port_result.graph.edges);
    stray_world_obligation_edges[world_port_result.graph.edges.len] = .{
        .kind = .opens_obligation,
        .from = second_shape.evidenceRef(),
        .to = world_port_result.report.world_port_refs[0],
        .label = "stray-world-port-obligation",
    };
    const stray_world_obligation_graph = Closure.Graph.init(
        "forged-stray-world-port-obligation",
        world_port_result.graph.nodes,
        stray_world_obligation_edges,
        world_port_result.graph.dependencies,
    );
    var stray_world_obligation_report = world_port_result.report;
    stray_world_obligation_report.graph_fingerprint = stray_world_obligation_graph.fingerprint;
    stray_world_obligation_report.report_fingerprint = stray_world_obligation_report.computeFingerprint();
    const stray_world_obligation_certificate = Evidence.BoundaryClosureCertificate.init(
        stray_world_obligation_report,
        stray_world_obligation_graph,
        world_port_only_policy,
        world_port_result.plan_refs,
    );
    try std.testing.expectError(
        error.BoundaryClosureCertificateMismatch,
        stray_world_obligation_certificate.check(stray_world_obligation_graph, stray_world_obligation_report, world_port_only_policy, world_port_result.static_treaty_plans),
    );

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
        error.BoundaryClosureCertificateMismatch,
        overcounted_world_cert.check(world_port_result.graph, overcounted_world_report, world_port_only_policy, world_port_result.static_treaty_plans),
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
        disallowed_world_certificate.check(world_port_result.graph, disallowed_world_report, disallowed_world_policy, world_port_result.static_treaty_plans),
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
    const root_branch_a = Evidence.refFor(Evidence.domains.program_plan, 0xC105EAA, .{ .label = "branch-stable-root", .branch_id = 1, .site_index = 1 });
    const root_branch_b = Evidence.refFor(Evidence.domains.program_plan, 0xC105EAA, .{ .label = "branch-stable-root", .branch_id = 2, .site_index = 1 });
    var root_order_ab = try Closure.analyze(allocator, .{
        .allocator = allocator,
        .root_program_refs = &.{ root_branch_a, root_branch_b },
        .policy = closure_policy,
    });
    defer root_order_ab.deinit();
    var root_order_ba = try Closure.analyze(allocator, .{
        .allocator = allocator,
        .root_program_refs = &.{ root_branch_b, root_branch_a },
        .policy = closure_policy,
    });
    defer root_order_ba.deinit();
    try std.testing.expectEqual(root_order_ab.graph.fingerprint, root_order_ba.graph.fingerprint);
    var stale_graph = result.graph;
    stale_graph.label = "stale-graph";
    try std.testing.expectError(
        error.BoundaryClosureGraphMismatch,
        result.certificate.check(stale_graph, result.report, closure_policy, result.static_treaty_plans),
    );
    var stale_report = result.report;
    stale_report.closed_effect_shape_count = 0;
    try std.testing.expectError(
        error.BoundaryClosureReportMismatch,
        result.certificate.check(result.graph, stale_report, closure_policy, result.static_treaty_plans),
    );
    try std.testing.expectError(
        error.BoundaryClosurePolicyMismatch,
        result.certificate.check(result.graph, result.report, Evidence.BoundaryClosurePolicy.strict(), result.static_treaty_plans),
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
        stale_policy_certificate.check(result.graph, stale_policy_report, closure_policy, result.static_treaty_plans),
    );
    var missing_plan_ref_certificate = result.certificate;
    missing_plan_ref_certificate.selected_static_treaty_plan_refs = &.{};
    missing_plan_ref_certificate.certificate_fingerprint = missing_plan_ref_certificate.computeFingerprint();
    try std.testing.expectError(
        error.BoundaryClosureCertificateMismatch,
        missing_plan_ref_certificate.check(result.graph, result.report, closure_policy, result.static_treaty_plans),
    );
    const forged_static_plan_ref = Evidence.refFor(Evidence.domains.boundary_static_treaty_plan, 0xDEADBEEF, .{ .label = "forged-plan" });
    var forged_plan_ref_certificate = result.certificate;
    forged_plan_ref_certificate.selected_static_treaty_plan_refs = &.{forged_static_plan_ref};
    forged_plan_ref_certificate.certificate_fingerprint = forged_plan_ref_certificate.computeFingerprint();
    try std.testing.expectError(
        error.BoundaryClosureCertificateMismatch,
        forged_plan_ref_certificate.check(result.graph, result.report, closure_policy, result.static_treaty_plans),
    );
    const forged_plan_nodes = try allocator.dupe(Closure.Graph.Node, result.graph.nodes);
    defer allocator.free(forged_plan_nodes);
    for (forged_plan_nodes) |*node| {
        if (node.kind == .treaty_shape_plan) {
            node.ref = forged_static_plan_ref;
            node.label = "forged-plan";
            break;
        }
    }
    const forged_plan_graph_edges = try allocator.dupe(Closure.Graph.Edge, result.graph.edges);
    defer allocator.free(forged_plan_graph_edges);
    for (forged_plan_graph_edges) |*edge| {
        if (edge.kind == .treaty_planned) {
            edge.to = forged_static_plan_ref;
            break;
        }
    }
    const forged_plan_graph = Closure.Graph.init(result.graph.label, forged_plan_nodes, forged_plan_graph_edges, result.graph.dependencies);
    var forged_plan_report = result.report;
    forged_plan_report.graph_fingerprint = forged_plan_graph.fingerprint;
    forged_plan_report.report_fingerprint = forged_plan_report.computeFingerprint();
    const forged_plan_certificate = Evidence.BoundaryClosureCertificate.init(
        forged_plan_report,
        forged_plan_graph,
        closure_policy,
        &.{forged_static_plan_ref},
    );
    try std.testing.expectError(
        error.BoundaryClosureCertificateMismatch,
        forged_plan_certificate.check(forged_plan_graph, forged_plan_report, closure_policy, result.static_treaty_plans),
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
        forged_plan_edge_certificate.check(forged_plan_edge_graph, forged_plan_edge_report, closure_policy, result.static_treaty_plans),
    );
    const duplicate_plan_edges = try allocator.alloc(Closure.Graph.Edge, result.graph.edges.len + 1);
    defer allocator.free(duplicate_plan_edges);
    @memcpy(duplicate_plan_edges[0..result.graph.edges.len], result.graph.edges);
    duplicate_plan_edges[result.graph.edges.len] = .{
        .kind = .treaty_planned,
        .from = shape.evidenceRef(),
        .to = result.static_treaty_plans[0].evidenceRef(),
    };
    const duplicate_plan_edge_graph = Closure.Graph.init(result.graph.label, result.graph.nodes, duplicate_plan_edges, result.graph.dependencies);
    var duplicate_plan_edge_report = result.report;
    duplicate_plan_edge_report.graph_fingerprint = duplicate_plan_edge_graph.fingerprint;
    duplicate_plan_edge_report.report_fingerprint = duplicate_plan_edge_report.computeFingerprint();
    const duplicate_plan_edge_certificate = Evidence.BoundaryClosureCertificate.init(
        duplicate_plan_edge_report,
        duplicate_plan_edge_graph,
        closure_policy,
        result.plan_refs,
    );
    try std.testing.expectError(
        error.BoundaryClosureCertificateMismatch,
        duplicate_plan_edge_certificate.check(duplicate_plan_edge_graph, duplicate_plan_edge_report, closure_policy, result.static_treaty_plans),
    );
    const forged_provider_offer_ref = Evidence.refFor(Evidence.domains.provider_offer, 0xFA110FF3, .{ .label = "unselected-provider-offer" });
    const forged_capability_ref = Evidence.refFor(Evidence.domains.capability, 0xFA11CA9A, .{ .label = "unselected-capability" });
    const forged_morphism_ref = Evidence.refFor(Evidence.domains.morphism_offer, 0xFA110D1A, .{ .label = "unselected-morphism" });
    const forged_route_cases = [_]struct {
        node_kind: Closure.Graph.NodeKind,
        edge_kind: Closure.Graph.EdgeKind,
        ref: Evidence.Ref,
        label: []const u8,
    }{
        .{ .node_kind = .provider_offer, .edge_kind = .handled_by_provider, .ref = forged_provider_offer_ref, .label = "forged-provider-route" },
        .{ .node_kind = .capability_grant, .edge_kind = .authorized_by_capability, .ref = forged_capability_ref, .label = "forged-capability-route" },
        .{ .node_kind = .morphism_offer, .edge_kind = .adapted_by_morphism, .ref = forged_morphism_ref, .label = "forged-morphism-route" },
    };
    for (forged_route_cases) |case| {
        const forged_route_nodes = try allocator.alloc(Closure.Graph.Node, result.graph.nodes.len + 1);
        defer allocator.free(forged_route_nodes);
        @memcpy(forged_route_nodes[0..result.graph.nodes.len], result.graph.nodes);
        forged_route_nodes[result.graph.nodes.len] = .{ .kind = case.node_kind, .ref = case.ref, .label = case.label };
        const forged_route_edges = try allocator.alloc(Closure.Graph.Edge, result.graph.edges.len + 1);
        defer allocator.free(forged_route_edges);
        @memcpy(forged_route_edges[0..result.graph.edges.len], result.graph.edges);
        forged_route_edges[result.graph.edges.len] = .{
            .kind = case.edge_kind,
            .from = shape.evidenceRef(),
            .to = case.ref,
            .label = case.label,
        };
        const forged_route_graph = Closure.Graph.init(case.label, forged_route_nodes, forged_route_edges, result.graph.dependencies);
        var forged_route_report = result.report;
        forged_route_report.graph_fingerprint = forged_route_graph.fingerprint;
        forged_route_report.report_fingerprint = forged_route_report.computeFingerprint();
        const forged_route_certificate = Evidence.BoundaryClosureCertificate.init(
            forged_route_report,
            forged_route_graph,
            closure_policy,
            result.plan_refs,
        );
        try std.testing.expectError(
            error.BoundaryClosureCertificateMismatch,
            forged_route_certificate.check(forged_route_graph, forged_route_report, closure_policy, result.static_treaty_plans),
        );
    }
    var bounded_node_policy = closure_policy;
    bounded_node_policy.max_nodes = result.graph.nodes.len;
    const forged_extra_node_ref = Evidence.refFor(Evidence.domains.provider_offer, 0xFA11B000, .{ .label = "extra-node-over-policy-bound" });
    const forged_extra_nodes = try allocator.alloc(Closure.Graph.Node, result.graph.nodes.len + 1);
    defer allocator.free(forged_extra_nodes);
    @memcpy(forged_extra_nodes[0..result.graph.nodes.len], result.graph.nodes);
    forged_extra_nodes[result.graph.nodes.len] = .{ .kind = .provider_offer, .ref = forged_extra_node_ref, .label = "extra-node-over-policy-bound" };
    const forged_extra_node_graph = Closure.Graph.init("extra-node-over-policy-bound", forged_extra_nodes, result.graph.edges, result.graph.dependencies);
    var forged_extra_node_report = result.report;
    forged_extra_node_report.graph_fingerprint = forged_extra_node_graph.fingerprint;
    forged_extra_node_report.policy_summary = bounded_node_policy.policySummary();
    forged_extra_node_report.report_fingerprint = forged_extra_node_report.computeFingerprint();
    const forged_extra_node_certificate = Evidence.BoundaryClosureCertificate.init(
        forged_extra_node_report,
        forged_extra_node_graph,
        bounded_node_policy,
        result.plan_refs,
    );
    try std.testing.expectError(
        error.BoundaryClosureCertificateMismatch,
        forged_extra_node_certificate.check(forged_extra_node_graph, forged_extra_node_report, bounded_node_policy, result.static_treaty_plans),
    );
    const forged_root_domain_ref = provider.evidenceRef();
    const forged_root_domain_nodes = try allocator.alloc(Closure.Graph.Node, result.graph.nodes.len + 1);
    defer allocator.free(forged_root_domain_nodes);
    @memcpy(forged_root_domain_nodes[0..result.graph.nodes.len], result.graph.nodes);
    forged_root_domain_nodes[result.graph.nodes.len] = .{
        .kind = .root_program,
        .ref = forged_root_domain_ref,
        .label = "forged-root-domain",
    };
    const forged_root_domain_edges = try allocator.alloc(Closure.Graph.Edge, result.graph.edges.len + 1);
    defer allocator.free(forged_root_domain_edges);
    @memcpy(forged_root_domain_edges[0..result.graph.edges.len], result.graph.edges);
    forged_root_domain_edges[result.graph.edges.len] = .{
        .kind = .root_yields,
        .from = forged_root_domain_ref,
        .to = shape.evidenceRef(),
        .label = "forged-root-domain",
    };
    const forged_root_domain_graph = Closure.Graph.init(
        "forged-root-domain-graph",
        forged_root_domain_nodes,
        forged_root_domain_edges,
        result.graph.dependencies,
    );
    var forged_root_domain_report = result.report;
    forged_root_domain_report.graph_fingerprint = forged_root_domain_graph.fingerprint;
    forged_root_domain_report.root_program_refs = &.{forged_root_domain_ref};
    forged_root_domain_report.report_fingerprint = forged_root_domain_report.computeFingerprint();
    const forged_root_domain_certificate = Evidence.BoundaryClosureCertificate.init(
        forged_root_domain_report,
        forged_root_domain_graph,
        closure_policy,
        result.plan_refs,
    );
    try std.testing.expectError(
        error.BoundaryClosureCertificateMismatch,
        forged_root_domain_certificate.check(forged_root_domain_graph, forged_root_domain_report, closure_policy, result.static_treaty_plans),
    );
    const forged_root_label_nodes = try allocator.alloc(Closure.Graph.Node, result.graph.nodes.len + 1);
    defer allocator.free(forged_root_label_nodes);
    @memcpy(forged_root_label_nodes[0..result.graph.nodes.len], result.graph.nodes);
    forged_root_label_nodes[result.graph.nodes.len] = .{
        .kind = .root_program,
        .ref = mismatched_label_root_ref,
        .label = "mismatched-root-program",
    };
    const forged_root_label_edges = try allocator.alloc(Closure.Graph.Edge, result.graph.edges.len + 1);
    defer allocator.free(forged_root_label_edges);
    @memcpy(forged_root_label_edges[0..result.graph.edges.len], result.graph.edges);
    forged_root_label_edges[result.graph.edges.len] = .{
        .kind = .root_yields,
        .from = mismatched_label_root_ref,
        .to = shape.evidenceRef(),
        .label = "mismatched-root-program",
    };
    const forged_root_label_graph = Closure.Graph.init(
        "forged-root-label-graph",
        forged_root_label_nodes,
        forged_root_label_edges,
        result.graph.dependencies,
    );
    var forged_root_label_report = result.report;
    forged_root_label_report.graph_fingerprint = forged_root_label_graph.fingerprint;
    forged_root_label_report.root_program_refs = &.{mismatched_label_root_ref};
    forged_root_label_report.report_fingerprint = forged_root_label_report.computeFingerprint();
    const forged_root_label_certificate = Evidence.BoundaryClosureCertificate.init(
        forged_root_label_report,
        forged_root_label_graph,
        closure_policy,
        result.plan_refs,
    );
    try std.testing.expectError(
        error.BoundaryClosureCertificateMismatch,
        forged_root_label_certificate.check(forged_root_label_graph, forged_root_label_report, closure_policy, result.static_treaty_plans),
    );
    var forged_provider_domain_plan = result.static_treaty_plans[0];
    forged_provider_domain_plan.selected_provider_ref = Evidence.refFor(Evidence.domains.provider_identity, provider.provider_fingerprint, .{ .label = provider.label });
    forged_provider_domain_plan.fingerprint = forged_provider_domain_plan.computeFingerprint();
    const forged_provider_domain_plan_ref = forged_provider_domain_plan.evidenceRef();
    const forged_provider_domain_nodes = try allocator.dupe(Closure.Graph.Node, result.graph.nodes);
    defer allocator.free(forged_provider_domain_nodes);
    for (forged_provider_domain_nodes) |*node| {
        if (node.kind == .treaty_shape_plan) {
            node.ref = forged_provider_domain_plan_ref;
            node.label = forged_provider_domain_plan.label;
            break;
        }
    }
    const forged_provider_domain_edges = try allocator.dupe(Closure.Graph.Edge, result.graph.edges);
    defer allocator.free(forged_provider_domain_edges);
    for (forged_provider_domain_edges) |*edge| {
        if (edge.kind == .treaty_planned) {
            edge.to = forged_provider_domain_plan_ref;
            break;
        }
    }
    const forged_provider_domain_graph = Closure.Graph.init(
        "forged-provider-domain-graph",
        forged_provider_domain_nodes,
        forged_provider_domain_edges,
        result.graph.dependencies,
    );
    var forged_provider_domain_report = result.report;
    forged_provider_domain_report.graph_fingerprint = forged_provider_domain_graph.fingerprint;
    forged_provider_domain_report.report_fingerprint = forged_provider_domain_report.computeFingerprint();
    const forged_provider_domain_certificate = Evidence.BoundaryClosureCertificate.init(
        forged_provider_domain_report,
        forged_provider_domain_graph,
        closure_policy,
        &.{forged_provider_domain_plan_ref},
    );
    const forged_provider_domain_plans = [_]Closure.StaticTreatyPlan{forged_provider_domain_plan};
    try std.testing.expectError(
        error.BoundaryClosureCertificateMismatch,
        forged_provider_domain_certificate.check(forged_provider_domain_graph, forged_provider_domain_report, closure_policy, forged_provider_domain_plans[0..]),
    );
    var forged_provider_attestation_plan = result.static_treaty_plans[0];
    forged_provider_attestation_plan.selected_provider_ref = impostor_provider.evidenceRef();
    forged_provider_attestation_plan.fingerprint = forged_provider_attestation_plan.computeFingerprint();
    const forged_provider_attestation_plan_ref = forged_provider_attestation_plan.evidenceRef();
    const forged_attestation_nodes = try allocator.dupe(Closure.Graph.Node, result.graph.nodes);
    defer allocator.free(forged_attestation_nodes);
    for (forged_attestation_nodes) |*node| {
        if (node.kind == .treaty_shape_plan) {
            node.ref = forged_provider_attestation_plan_ref;
            node.label = forged_provider_attestation_plan.label;
            break;
        }
    }
    const forged_attestation_edges = try allocator.dupe(Closure.Graph.Edge, result.graph.edges);
    defer allocator.free(forged_attestation_edges);
    for (forged_attestation_edges) |*edge| {
        if (edge.kind == .treaty_planned) {
            edge.to = forged_provider_attestation_plan_ref;
            break;
        }
    }
    const forged_provider_attestation_graph = Closure.Graph.init(
        "forged-provider-attestation-graph",
        forged_attestation_nodes,
        forged_attestation_edges,
        result.graph.dependencies,
    );
    var forged_provider_attestation_report = result.report;
    forged_provider_attestation_report.graph_fingerprint = forged_provider_attestation_graph.fingerprint;
    forged_provider_attestation_report.report_fingerprint = forged_provider_attestation_report.computeFingerprint();
    const forged_provider_attestation_certificate = Evidence.BoundaryClosureCertificate.init(
        forged_provider_attestation_report,
        forged_provider_attestation_graph,
        closure_policy,
        &.{forged_provider_attestation_plan_ref},
    );
    const forged_provider_attestation_plans = [_]Closure.StaticTreatyPlan{forged_provider_attestation_plan};
    try std.testing.expectError(
        error.BoundaryClosureCertificateMismatch,
        forged_provider_attestation_certificate.check(forged_provider_attestation_graph, forged_provider_attestation_report, closure_policy, forged_provider_attestation_plans[0..]),
    );
    const hidden_blocker_plan = try Closure.planTreatyForShape(.{
        .allocator = allocator,
        .shape = shape,
        .policy = closure_policy,
    });
    defer allocator.free(hidden_blocker_plan.blockers);
    defer allocator.free(hidden_blocker_plan.dependencies);
    try std.testing.expect(hidden_blocker_plan.blockers.len != 0);
    const hidden_blocker_plan_ref = hidden_blocker_plan.evidenceRef();
    const hidden_blocker_shape_ref = shape.evidenceRef();
    const hidden_blocker_nodes = [_]Closure.Graph.Node{
        .{ .kind = .operation_site, .ref = hidden_blocker_shape_ref, .label = shape.name },
        .{ .kind = .treaty_shape_plan, .ref = hidden_blocker_plan_ref, .label = hidden_blocker_plan.label },
    };
    const hidden_blocker_edges = [_]Closure.Graph.Edge{.{
        .kind = .treaty_planned,
        .from = hidden_blocker_shape_ref,
        .to = hidden_blocker_plan_ref,
    }};
    const hidden_blocker_graph = Closure.Graph.init("hidden-plan-blocker-graph", hidden_blocker_nodes[0..], hidden_blocker_edges[0..], &.{});
    const hidden_blocker_policy = Evidence.BoundaryClosurePolicy.auditOnly();
    const hidden_blocker_report = Evidence.BoundaryClosureReport.init(.{
        .graph_fingerprint = hidden_blocker_graph.fingerprint,
        .effect_shape_count = 1,
        .policy_summary = hidden_blocker_policy.policySummary(),
    });
    const hidden_blocker_certificate = Evidence.BoundaryClosureCertificate.init(
        hidden_blocker_report,
        hidden_blocker_graph,
        hidden_blocker_policy,
        &.{hidden_blocker_plan_ref},
    );
    try std.testing.expectError(
        error.BoundaryClosureCertificateMismatch,
        hidden_blocker_certificate.check(hidden_blocker_graph, hidden_blocker_report, hidden_blocker_policy, &.{hidden_blocker_plan}),
    );
    var stale_count_certificate = result.certificate;
    stale_count_certificate.closed_effect_shape_count = 0;
    stale_count_certificate.certificate_fingerprint = stale_count_certificate.computeFingerprint();
    try std.testing.expectError(
        error.BoundaryClosureCertificateMismatch,
        stale_count_certificate.check(result.graph, result.report, closure_policy, result.static_treaty_plans),
    );
    var stale_format_certificate = result.certificate;
    stale_format_certificate.certificate_format_version += 1;
    stale_format_certificate.certificate_fingerprint = stale_format_certificate.computeFingerprint();
    try std.testing.expectError(
        error.BoundaryClosureCertificateMismatch,
        stale_format_certificate.check(result.graph, result.report, closure_policy, result.static_treaty_plans),
    );
    var forged_route_mix_report = result.report;
    forged_route_mix_report.intrinsic_route_count = 0;
    forged_route_mix_report.report_fingerprint = forged_route_mix_report.computeFingerprint();
    const forged_route_mix_certificate = Evidence.BoundaryClosureCertificate.init(
        forged_route_mix_report,
        result.graph,
        closure_policy,
        result.plan_refs,
    );
    try std.testing.expectError(
        error.BoundaryClosureCertificateMismatch,
        forged_route_mix_certificate.check(result.graph, forged_route_mix_report, closure_policy, result.static_treaty_plans),
    );
    const unplanned_shape_plan = Evidence.BoundaryStaticTreatyPlan.init(.{
        .label = "unplanned-shape",
        .source_shape = shape,
    });
    const unplanned_nodes = [_]Closure.Graph.Node{
        .{ .kind = .operation_site, .ref = shape.evidenceRef(), .label = shape.name },
        .{ .kind = .treaty_shape_plan, .ref = unplanned_shape_plan.evidenceRef(), .label = unplanned_shape_plan.label },
    };
    const unplanned_edges = [_]Closure.Graph.Edge{
        .{ .kind = .treaty_planned, .from = shape.evidenceRef(), .to = unplanned_shape_plan.evidenceRef() },
    };
    const unplanned_graph = Closure.Graph.init("unplanned-static-treaty-graph", unplanned_nodes[0..], unplanned_edges[0..], &.{});
    const unplanned_report = Evidence.BoundaryClosureReport.init(.{
        .graph_fingerprint = unplanned_graph.fingerprint,
        .effect_shape_count = 1,
        .policy_summary = audit_policy.policySummary(),
    });
    const unplanned_plan_refs = [_]Evidence.Ref{unplanned_shape_plan.evidenceRef()};
    const unplanned_certificate = Evidence.BoundaryClosureCertificate.init(
        unplanned_report,
        unplanned_graph,
        audit_policy,
        unplanned_plan_refs[0..],
    );
    const unplanned_plans = [_]Evidence.BoundaryStaticTreatyPlan{unplanned_shape_plan};
    try std.testing.expectError(
        error.BoundaryClosureCertificateMismatch,
        unplanned_certificate.check(unplanned_graph, unplanned_report, audit_policy, unplanned_plans[0..]),
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
        forged_world_certificate.check(result.graph, forged_world_report, restricted_world_policy, result.static_treaty_plans),
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
        forged_program_cert.check(result.graph, forged_provider_program_report, closure_policy, result.static_treaty_plans),
    );
    const program_backed_ref = Evidence.refFor(Evidence.domains.program_plan, 0xBACCED, .{ .label = "program-backed-provider" });
    const nested_shape = Evidence.BoundaryEffectShape.init(.{
        .program_label = "program-backed-provider",
        .plan_label = "nested-evidence-test-plan",
        .plan_hash = 0xBACCED,
        .manifest_fingerprint = manifest.fingerprint,
        .kind = .operation,
        .site_index = site_index + 1,
        .site_fingerprint = protocol_op_fingerprint + 1,
        .semantic_label = "nested-approval",
        .name = "nested-approve",
        .mode = "transform",
        .value_ref = Evidence.BoundaryValueRef.fromValueRef(payload_ref),
        .expected_resume_ref = Evidence.BoundaryValueRef.fromValueRef(response_ref),
        .protocol_label = "approval",
        .protocol_op_fingerprint = protocol_op_fingerprint + 1,
    });
    const per_shape_world_plan = Evidence.BoundaryStaticTreatyPlan.init(.{
        .label = "per-shape-world-plan",
        .source_shape = shape,
        .selected_provider_offer_ref = offer.evidenceRef(),
        .selected_provider_ref = provider.evidenceRef(),
        .selected_capability_ref = capability.evidenceRef(),
        .selected_semantic_body = .host_intrinsic,
        .selected_intrinsic_ref = offer_intrinsic_ref,
        .host_intrinsic = true,
    });
    const per_shape_unexposed_plan = Evidence.BoundaryStaticTreatyPlan.init(.{
        .label = "per-shape-unexposed-plan",
        .source_shape = nested_shape,
        .selected_provider_offer_ref = offer.evidenceRef(),
        .selected_provider_ref = provider.evidenceRef(),
        .selected_capability_ref = capability.evidenceRef(),
        .selected_semantic_body = .host_intrinsic,
        .selected_intrinsic_ref = offer_intrinsic_ref,
        .host_intrinsic = true,
    });
    const per_shape_plan_refs = [_]Evidence.Ref{ per_shape_world_plan.evidenceRef(), per_shape_unexposed_plan.evidenceRef() };
    const per_shape_nodes = [_]Closure.Graph.Node{
        .{ .kind = .operation_site, .ref = shape.evidenceRef(), .label = shape.name },
        .{ .kind = .operation_site, .ref = nested_shape.evidenceRef(), .label = nested_shape.name },
        .{ .kind = .treaty_shape_plan, .ref = per_shape_world_plan.evidenceRef(), .label = per_shape_world_plan.label },
        .{ .kind = .treaty_shape_plan, .ref = per_shape_unexposed_plan.evidenceRef(), .label = per_shape_unexposed_plan.label },
        .{ .kind = .provider_manifest, .ref = provider.evidenceRef(), .label = provider.label },
        .{ .kind = .provider_offer, .ref = offer.evidenceRef(), .label = offer.label },
        .{ .kind = .capability_grant, .ref = capability.evidenceRef(), .label = capability.issuer_label },
        .{ .kind = .host_intrinsic, .ref = offer_intrinsic_ref, .label = "shared-host-intrinsic" },
        .{ .kind = .world_port, .ref = forged_world_port_ref, .label = "shape-local-world-port" },
    };
    const per_shape_edges = [_]Closure.Graph.Edge{
        .{ .kind = .treaty_planned, .from = shape.evidenceRef(), .to = per_shape_world_plan.evidenceRef() },
        .{ .kind = .provider_advertises_offer, .from = provider.evidenceRef(), .to = offer.evidenceRef() },
        .{ .kind = .handled_by_provider, .from = shape.evidenceRef(), .to = offer.evidenceRef() },
        .{ .kind = .authorized_by_capability, .from = shape.evidenceRef(), .to = capability.evidenceRef() },
        .{ .kind = .intrinsic_boundary, .from = shape.evidenceRef(), .to = offer_intrinsic_ref },
        .{ .kind = .opens_obligation, .from = shape.evidenceRef(), .to = forged_world_port_ref },
        .{ .kind = .world_port_exposes, .from = offer_intrinsic_ref, .to = forged_world_port_ref },
        .{ .kind = .treaty_planned, .from = nested_shape.evidenceRef(), .to = per_shape_unexposed_plan.evidenceRef() },
        .{ .kind = .handled_by_provider, .from = nested_shape.evidenceRef(), .to = offer.evidenceRef() },
        .{ .kind = .authorized_by_capability, .from = nested_shape.evidenceRef(), .to = capability.evidenceRef() },
        .{ .kind = .intrinsic_boundary, .from = nested_shape.evidenceRef(), .to = offer_intrinsic_ref },
    };
    const per_shape_graph = Closure.Graph.init("per-shape-world-port-proof", per_shape_nodes[0..], per_shape_edges[0..], &.{});
    const per_shape_world_refs = [_]Evidence.Ref{forged_world_port_ref};
    const per_shape_intrinsic_refs = [_]Evidence.Ref{offer_intrinsic_ref};
    var per_shape_policy = Evidence.BoundaryClosurePolicy.auditOnly();
    per_shape_policy.reject_host_intrinsics = true;
    per_shape_policy.allow_world_ports = true;
    const per_shape_allowed_ports = [_]u64{forged_world_port_ref.fingerprint};
    per_shape_policy.allowed_world_port_fingerprints = per_shape_allowed_ports[0..];
    const per_shape_report = Evidence.BoundaryClosureReport.init(.{
        .graph_fingerprint = per_shape_graph.fingerprint,
        .effect_shape_count = 2,
        .closed_effect_shape_count = 0,
        .open_world_port_count = 1,
        .host_intrinsic_count = 1,
        .intrinsic_route_count = 0,
        .world_port_refs = per_shape_world_refs[0..],
        .world_port_intrinsic_refs = per_shape_intrinsic_refs[0..],
        .host_intrinsic_refs = per_shape_intrinsic_refs[0..],
        .policy_summary = per_shape_policy.policySummary(),
    });
    const per_shape_certificate = Evidence.BoundaryClosureCertificate.init(
        per_shape_report,
        per_shape_graph,
        per_shape_policy,
        per_shape_plan_refs[0..],
    );
    const per_shape_plans = [_]Evidence.BoundaryStaticTreatyPlan{ per_shape_world_plan, per_shape_unexposed_plan };
    try std.testing.expectError(
        error.BoundaryClosureIntrinsicRejected,
        per_shape_certificate.check(per_shape_graph, per_shape_report, per_shape_policy, per_shape_plans[0..]),
    );
    const program_backed_plan = Evidence.BoundaryStaticTreatyPlan.init(.{
        .label = "program-backed-provider-plan",
        .source_shape = shape,
        .selected_provider_offer_ref = offer.evidenceRef(),
        .selected_provider_ref = provider.evidenceRef(),
        .selected_capability_ref = capability.evidenceRef(),
        .selected_semantic_body = .boundary_program,
        .selected_provider_program_ref = program_backed_ref,
        .selected_provider_program_mapping_fingerprint = 0xBACCED01,
        .selected_provider_program_request_mapping_tag = "payload_to_args",
        .selected_provider_program_result_mapping_tag = "result_to_resume",
        .selected_provider_program_effect_shape_count = 1,
        .selected_provider_program_effect_shape_fingerprint = Evidence.fingerprintBoundaryEffectShapeSet(&.{nested_shape}),
    });
    const nested_plan = Evidence.BoundaryStaticTreatyPlan.init(.{
        .label = "nested-provider-plan",
        .source_shape = nested_shape,
        .selected_provider_offer_ref = offer.evidenceRef(),
        .selected_provider_ref = provider.evidenceRef(),
        .selected_capability_ref = capability.evidenceRef(),
        .selected_semantic_body = .declarative,
    });
    const program_backed_plan_refs = [_]Evidence.Ref{ program_backed_plan.evidenceRef(), nested_plan.evidenceRef() };
    const program_backed_mapping_ref = Evidence.refForProviderProgramMapping(program_backed_plan.selected_provider_program_mapping_support_fingerprint.?);
    const program_backed_nodes = [_]Closure.Graph.Node{
        .{ .kind = .operation_site, .ref = shape.evidenceRef(), .label = shape.name },
        .{ .kind = .operation_site, .ref = nested_shape.evidenceRef(), .label = nested_shape.name },
        .{ .kind = .treaty_shape_plan, .ref = program_backed_plan.evidenceRef(), .label = program_backed_plan.label },
        .{ .kind = .treaty_shape_plan, .ref = nested_plan.evidenceRef(), .label = nested_plan.label },
        .{ .kind = .provider_manifest, .ref = provider.evidenceRef(), .label = provider.label },
        .{ .kind = .provider_offer, .ref = offer.evidenceRef(), .label = offer.label },
        .{ .kind = .capability_grant, .ref = capability.evidenceRef(), .label = capability.issuer_label },
        .{ .kind = .provider_program, .ref = program_backed_ref, .label = "program-backed-provider" },
        .{ .kind = .provider_program_mapping, .ref = program_backed_mapping_ref, .label = "program-backed-mapping" },
    };
    const program_backed_edges = [_]Closure.Graph.Edge{
        .{ .kind = .treaty_planned, .from = shape.evidenceRef(), .to = program_backed_plan.evidenceRef() },
        .{ .kind = .provider_advertises_offer, .from = provider.evidenceRef(), .to = offer.evidenceRef() },
        .{ .kind = .handled_by_provider, .from = shape.evidenceRef(), .to = offer.evidenceRef() },
        .{ .kind = .authorized_by_capability, .from = shape.evidenceRef(), .to = capability.evidenceRef() },
        .{ .kind = .provider_program_mapped_by, .from = program_backed_ref, .to = program_backed_mapping_ref },
        .{ .kind = .provider_program_yields, .from = program_backed_ref, .to = nested_shape.evidenceRef() },
        .{ .kind = .treaty_planned, .from = nested_shape.evidenceRef(), .to = nested_plan.evidenceRef() },
        .{ .kind = .handled_by_provider, .from = nested_shape.evidenceRef(), .to = offer.evidenceRef() },
        .{ .kind = .authorized_by_capability, .from = nested_shape.evidenceRef(), .to = capability.evidenceRef() },
    };
    const program_backed_graph = Closure.Graph.init("program-backed-provider-proof", program_backed_nodes[0..], program_backed_edges[0..], &.{});
    const program_backed_provider_refs = [_]Evidence.Ref{program_backed_ref};
    const program_backed_policy = Evidence.BoundaryClosurePolicy.auditOnly();
    const program_backed_report = Evidence.BoundaryClosureReport.init(.{
        .graph_fingerprint = program_backed_graph.fingerprint,
        .effect_shape_count = 2,
        .closed_effect_shape_count = 2,
        .provider_program_refs = program_backed_provider_refs[0..],
        .declarative_route_count = 1,
        .policy_summary = program_backed_policy.policySummary(),
    });
    const program_backed_certificate = Evidence.BoundaryClosureCertificate.init(
        program_backed_report,
        program_backed_graph,
        program_backed_policy,
        program_backed_plan_refs[0..],
    );
    const program_backed_plans = [_]Evidence.BoundaryStaticTreatyPlan{ program_backed_plan, nested_plan };
    try program_backed_certificate.check(program_backed_graph, program_backed_report, program_backed_policy, program_backed_plans[0..]);
    var zero_depth_program_policy = program_backed_policy;
    zero_depth_program_policy.max_nested_provider_depth = 0;
    const zero_depth_program_report = Evidence.BoundaryClosureReport.init(.{
        .graph_fingerprint = program_backed_graph.fingerprint,
        .effect_shape_count = 2,
        .closed_effect_shape_count = 2,
        .provider_program_refs = program_backed_provider_refs[0..],
        .declarative_route_count = 1,
        .policy_summary = zero_depth_program_policy.policySummary(),
    });
    const zero_depth_program_certificate = Evidence.BoundaryClosureCertificate.init(
        zero_depth_program_report,
        program_backed_graph,
        zero_depth_program_policy,
        program_backed_plan_refs[0..],
    );
    try std.testing.expectError(
        error.BoundaryClosureCertificateMismatch,
        zero_depth_program_certificate.check(program_backed_graph, zero_depth_program_report, zero_depth_program_policy, program_backed_plans[0..]),
    );
    const unrelated_program_ref = Evidence.refFor(Evidence.domains.program_plan, 0xDEAD_B10C, .{ .label = "unrelated-provider-program" });
    const unrelated_blocker = Evidence.boundaryClosureBlocker(.{
        .tag = .provider_program_contract_missing,
        .subject = unrelated_program_ref,
        .summary = "unrelated provider program has no nested effect-shape proof",
    });
    const unrelated_blocker_ref = Evidence.refForBoundaryClosureBlocker(unrelated_blocker);
    const unrelated_blocked_nodes = try allocator.alloc(Closure.Graph.Node, program_backed_nodes.len + 1);
    defer allocator.free(unrelated_blocked_nodes);
    @memcpy(unrelated_blocked_nodes[0..program_backed_nodes.len], program_backed_nodes[0..]);
    unrelated_blocked_nodes[program_backed_nodes.len] = .{ .kind = .blocker, .ref = unrelated_blocker_ref, .label = unrelated_blocker.summary };
    const unrelated_blocked_edges = try allocator.alloc(Closure.Graph.Edge, program_backed_edges.len + 1);
    defer allocator.free(unrelated_blocked_edges);
    @memcpy(unrelated_blocked_edges[0..program_backed_edges.len], program_backed_edges[0..]);
    unrelated_blocked_edges[program_backed_edges.len] = .{ .kind = .blocked_by, .from = unrelated_program_ref, .to = unrelated_blocker_ref };
    const unrelated_blocked_graph = Closure.Graph.init("program-backed-provider-unrelated-blocker", unrelated_blocked_nodes, unrelated_blocked_edges, &.{});
    const unrelated_blockers = [_]Evidence.Blocker{unrelated_blocker};
    const unrelated_blocked_report = Evidence.BoundaryClosureReport.init(.{
        .graph_fingerprint = unrelated_blocked_graph.fingerprint,
        .effect_shape_count = 2,
        .closed_effect_shape_count = 2,
        .provider_program_refs = program_backed_provider_refs[0..],
        .blockers = unrelated_blockers[0..],
        .declarative_route_count = 1,
        .policy_summary = zero_depth_program_policy.policySummary(),
    });
    const unrelated_blocked_certificate = Evidence.BoundaryClosureCertificate.init(
        unrelated_blocked_report,
        unrelated_blocked_graph,
        zero_depth_program_policy,
        program_backed_plan_refs[0..],
    );
    try std.testing.expectError(
        error.BoundaryClosureCertificateMismatch,
        unrelated_blocked_certificate.check(unrelated_blocked_graph, unrelated_blocked_report, zero_depth_program_policy, program_backed_plans[0..]),
    );
    const extra_intrinsic_nodes = try allocator.alloc(Closure.Graph.Node, program_backed_nodes.len + 1);
    defer allocator.free(extra_intrinsic_nodes);
    @memcpy(extra_intrinsic_nodes[0..program_backed_nodes.len], program_backed_nodes[0..]);
    extra_intrinsic_nodes[program_backed_nodes.len] = .{ .kind = .host_intrinsic, .ref = forged_intrinsic_ref, .label = "unselected-host-intrinsic" };
    const extra_intrinsic_edges = try allocator.alloc(Closure.Graph.Edge, program_backed_edges.len + 1);
    defer allocator.free(extra_intrinsic_edges);
    @memcpy(extra_intrinsic_edges[0..program_backed_edges.len], program_backed_edges[0..]);
    extra_intrinsic_edges[program_backed_edges.len] = .{ .kind = .intrinsic_boundary, .from = shape.evidenceRef(), .to = forged_intrinsic_ref };
    const extra_intrinsic_graph = Closure.Graph.init("unselected-host-intrinsic-edge", extra_intrinsic_nodes, extra_intrinsic_edges, &.{});
    const extra_intrinsic_report = Evidence.BoundaryClosureReport.init(.{
        .graph_fingerprint = extra_intrinsic_graph.fingerprint,
        .effect_shape_count = 2,
        .closed_effect_shape_count = 2,
        .provider_program_refs = program_backed_provider_refs[0..],
        .host_intrinsic_count = 1,
        .declarative_route_count = 1,
        .host_intrinsic_refs = forged_intrinsic_refs[0..],
        .policy_summary = program_backed_policy.policySummary(),
    });
    const extra_intrinsic_certificate = Evidence.BoundaryClosureCertificate.init(
        extra_intrinsic_report,
        extra_intrinsic_graph,
        program_backed_policy,
        program_backed_plan_refs[0..],
    );
    try std.testing.expectError(
        error.BoundaryClosureCertificateMismatch,
        extra_intrinsic_certificate.check(extra_intrinsic_graph, extra_intrinsic_report, program_backed_policy, program_backed_plans[0..]),
    );
    const forged_mapping_plan = Evidence.BoundaryStaticTreatyPlan.init(.{
        .label = program_backed_plan.label,
        .source_shape = shape,
        .selected_provider_offer_ref = offer.evidenceRef(),
        .selected_provider_ref = provider.evidenceRef(),
        .selected_capability_ref = capability.evidenceRef(),
        .selected_semantic_body = .boundary_program,
        .selected_provider_program_ref = program_backed_ref,
        .selected_provider_program_mapping_fingerprint = 0xBACCED02,
        .selected_provider_program_request_mapping_tag = "payload_to_args",
        .selected_provider_program_result_mapping_tag = "result_to_resume",
        .selected_provider_program_effect_shape_count = 1,
        .selected_provider_program_effect_shape_fingerprint = Evidence.fingerprintBoundaryEffectShapeSet(&.{nested_shape}),
    });
    const forged_mapping_refs = [_]Evidence.Ref{ forged_mapping_plan.evidenceRef(), nested_plan.evidenceRef() };
    const forged_mapping_nodes = try allocator.dupe(Closure.Graph.Node, program_backed_nodes[0..]);
    defer allocator.free(forged_mapping_nodes);
    for (forged_mapping_nodes) |*node| {
        if (node.ref.eql(program_backed_plan.evidenceRef())) node.ref = forged_mapping_plan.evidenceRef();
    }
    const forged_mapping_edges = try allocator.dupe(Closure.Graph.Edge, program_backed_edges[0..]);
    defer allocator.free(forged_mapping_edges);
    for (forged_mapping_edges) |*edge| {
        if (edge.to.eql(program_backed_plan.evidenceRef())) edge.to = forged_mapping_plan.evidenceRef();
    }
    const forged_mapping_graph = Closure.Graph.init("forged-provider-program-mapping", forged_mapping_nodes, forged_mapping_edges, &.{});
    var forged_mapping_report = program_backed_report;
    forged_mapping_report.graph_fingerprint = forged_mapping_graph.fingerprint;
    forged_mapping_report.report_fingerprint = forged_mapping_report.computeFingerprint();
    const forged_mapping_certificate = Evidence.BoundaryClosureCertificate.init(
        forged_mapping_report,
        forged_mapping_graph,
        program_backed_policy,
        forged_mapping_refs[0..],
    );
    const forged_mapping_plans = [_]Evidence.BoundaryStaticTreatyPlan{ forged_mapping_plan, nested_plan };
    try std.testing.expectError(
        error.BoundaryClosureCertificateMismatch,
        forged_mapping_certificate.check(forged_mapping_graph, forged_mapping_report, program_backed_policy, forged_mapping_plans[0..]),
    );
    const forged_offer_ref = Evidence.refFor(Evidence.domains.provider_offer, 0xE75A_0A90, .{ .label = "alternate-program-backed-offer" });
    const forged_offer_plan = Evidence.BoundaryStaticTreatyPlan.init(.{
        .label = program_backed_plan.label,
        .source_shape = shape,
        .selected_provider_offer_ref = forged_offer_ref,
        .selected_provider_ref = provider.evidenceRef(),
        .selected_capability_ref = capability.evidenceRef(),
        .selected_semantic_body = .boundary_program,
        .selected_provider_program_ref = program_backed_ref,
        .selected_provider_program_mapping_fingerprint = program_backed_plan.selected_provider_program_mapping_fingerprint.?,
        .selected_provider_program_request_mapping_tag = "payload_to_args",
        .selected_provider_program_result_mapping_tag = "result_to_resume",
        .selected_provider_program_effect_shape_count = 1,
        .selected_provider_program_effect_shape_fingerprint = Evidence.fingerprintBoundaryEffectShapeSet(&.{nested_shape}),
    });
    const forged_offer_refs = [_]Evidence.Ref{ forged_offer_plan.evidenceRef(), nested_plan.evidenceRef() };
    const forged_offer_nodes = try allocator.dupe(Closure.Graph.Node, program_backed_nodes[0..]);
    defer allocator.free(forged_offer_nodes);
    for (forged_offer_nodes) |*node| {
        if (node.ref.eql(program_backed_plan.evidenceRef())) node.ref = forged_offer_plan.evidenceRef();
    }
    const forged_offer_edges = try allocator.dupe(Closure.Graph.Edge, program_backed_edges[0..]);
    defer allocator.free(forged_offer_edges);
    for (forged_offer_edges) |*edge| {
        if (edge.to.eql(program_backed_plan.evidenceRef())) edge.to = forged_offer_plan.evidenceRef();
    }
    const forged_offer_graph = Closure.Graph.init("forged-provider-program-offer-support", forged_offer_nodes, forged_offer_edges, &.{});
    var forged_offer_report = program_backed_report;
    forged_offer_report.graph_fingerprint = forged_offer_graph.fingerprint;
    forged_offer_report.report_fingerprint = forged_offer_report.computeFingerprint();
    const forged_offer_certificate = Evidence.BoundaryClosureCertificate.init(
        forged_offer_report,
        forged_offer_graph,
        program_backed_policy,
        forged_offer_refs[0..],
    );
    const forged_offer_plans = [_]Evidence.BoundaryStaticTreatyPlan{ forged_offer_plan, nested_plan };
    try std.testing.expectError(
        error.BoundaryClosureCertificateMismatch,
        forged_offer_certificate.check(forged_offer_graph, forged_offer_report, program_backed_policy, forged_offer_plans[0..]),
    );
    const extra_mapping_ref = Evidence.refForProviderProgramMapping(0xE75A_0A91);
    const extra_mapping_nodes = try allocator.alloc(Closure.Graph.Node, program_backed_nodes.len + 1);
    defer allocator.free(extra_mapping_nodes);
    @memcpy(extra_mapping_nodes[0..program_backed_nodes.len], program_backed_nodes[0..]);
    extra_mapping_nodes[program_backed_nodes.len] = .{ .kind = .provider_program_mapping, .ref = extra_mapping_ref, .label = "unselected-provider-program-mapping" };
    const extra_mapping_edges = try allocator.alloc(Closure.Graph.Edge, program_backed_edges.len + 1);
    defer allocator.free(extra_mapping_edges);
    @memcpy(extra_mapping_edges[0..program_backed_edges.len], program_backed_edges[0..]);
    extra_mapping_edges[program_backed_edges.len] = .{ .kind = .provider_program_mapped_by, .from = program_backed_ref, .to = extra_mapping_ref };
    const extra_mapping_graph = Closure.Graph.init("extra-provider-program-mapping-edge", extra_mapping_nodes, extra_mapping_edges, &.{});
    var extra_mapping_report = program_backed_report;
    extra_mapping_report.graph_fingerprint = extra_mapping_graph.fingerprint;
    extra_mapping_report.report_fingerprint = extra_mapping_report.computeFingerprint();
    const extra_mapping_certificate = Evidence.BoundaryClosureCertificate.init(
        extra_mapping_report,
        extra_mapping_graph,
        program_backed_policy,
        program_backed_plan_refs[0..],
    );
    try std.testing.expectError(
        error.BoundaryClosureCertificateMismatch,
        extra_mapping_certificate.check(extra_mapping_graph, extra_mapping_report, program_backed_policy, program_backed_plans[0..]),
    );
    const unattested_program_ref = Evidence.refFor(Evidence.domains.program_plan, 0xA77E57ED, .{ .label = "unattested-provider-program" });
    const extra_program_nodes = try allocator.alloc(Closure.Graph.Node, program_backed_nodes.len + 1);
    defer allocator.free(extra_program_nodes);
    @memcpy(extra_program_nodes[0..program_backed_nodes.len], program_backed_nodes[0..]);
    extra_program_nodes[program_backed_nodes.len] = .{ .kind = .provider_program, .ref = unattested_program_ref, .label = "unattested-provider-program" };
    const extra_program_graph = Closure.Graph.init("unattested-provider-program-proof", extra_program_nodes, program_backed_edges[0..], &.{});
    const extra_program_refs = [_]Evidence.Ref{ program_backed_ref, unattested_program_ref };
    var extra_program_report = program_backed_report;
    extra_program_report.graph_fingerprint = extra_program_graph.fingerprint;
    extra_program_report.provider_program_refs = extra_program_refs[0..];
    extra_program_report.report_fingerprint = extra_program_report.computeFingerprint();
    const extra_program_certificate = Evidence.BoundaryClosureCertificate.init(
        extra_program_report,
        extra_program_graph,
        program_backed_policy,
        program_backed_plan_refs[0..],
    );
    try std.testing.expectError(
        error.BoundaryClosureCertificateMismatch,
        extra_program_certificate.check(extra_program_graph, extra_program_report, program_backed_policy, program_backed_plans[0..]),
    );
    const unattested_yield_edges = try allocator.alloc(Closure.Graph.Edge, program_backed_edges.len + 1);
    defer allocator.free(unattested_yield_edges);
    @memcpy(unattested_yield_edges[0..program_backed_edges.len], program_backed_edges[0..]);
    unattested_yield_edges[program_backed_edges.len] = .{ .kind = .provider_program_yields, .from = unattested_program_ref, .to = nested_shape.evidenceRef(), .label = "unattested-provider-program-yield" };
    const unattested_yield_graph = Closure.Graph.init("unattested-provider-program-yield-edge", extra_program_nodes, unattested_yield_edges, &.{});
    var unattested_yield_report = program_backed_report;
    unattested_yield_report.graph_fingerprint = unattested_yield_graph.fingerprint;
    unattested_yield_report.report_fingerprint = unattested_yield_report.computeFingerprint();
    const unattested_yield_certificate = Evidence.BoundaryClosureCertificate.init(
        unattested_yield_report,
        unattested_yield_graph,
        program_backed_policy,
        program_backed_plan_refs[0..],
    );
    try std.testing.expectError(
        error.BoundaryClosureCertificateMismatch,
        unattested_yield_certificate.check(unattested_yield_graph, unattested_yield_report, program_backed_policy, program_backed_plans[0..]),
    );
    const forged_yield_plan = Evidence.BoundaryStaticTreatyPlan.init(.{
        .label = program_backed_plan.label,
        .source_shape = shape,
        .selected_provider_offer_ref = offer.evidenceRef(),
        .selected_provider_ref = provider.evidenceRef(),
        .selected_capability_ref = capability.evidenceRef(),
        .selected_semantic_body = .boundary_program,
        .selected_provider_program_ref = program_backed_ref,
        .selected_provider_program_mapping_fingerprint = program_backed_plan.selected_provider_program_mapping_fingerprint,
        .selected_provider_program_request_mapping_tag = "payload_to_args",
        .selected_provider_program_result_mapping_tag = "result_to_resume",
        .selected_provider_program_effect_shape_count = 2,
        .selected_provider_program_effect_shape_fingerprint = Evidence.fingerprintBoundaryEffectShapeSet(&.{ shape, nested_shape }),
    });
    const forged_program_refs = [_]Evidence.Ref{ forged_yield_plan.evidenceRef(), nested_plan.evidenceRef() };
    const forged_program_nodes = try allocator.dupe(Closure.Graph.Node, program_backed_nodes[0..]);
    defer allocator.free(forged_program_nodes);
    for (forged_program_nodes) |*node| {
        if (node.ref.eql(program_backed_plan.evidenceRef())) node.ref = forged_yield_plan.evidenceRef();
    }
    const forged_program_edges = try allocator.alloc(Closure.Graph.Edge, program_backed_edges.len + 1);
    defer allocator.free(forged_program_edges);
    @memcpy(forged_program_edges[0..program_backed_edges.len], program_backed_edges[0..]);
    for (forged_program_edges[0..program_backed_edges.len]) |*edge| {
        if (edge.to.eql(program_backed_plan.evidenceRef())) edge.to = forged_yield_plan.evidenceRef();
    }
    forged_program_edges[program_backed_edges.len] = .{ .kind = .provider_program_yields, .from = program_backed_ref, .to = shape.evidenceRef(), .label = "forged-provider-program-yield" };
    const forged_program_graph = Closure.Graph.init("forged-provider-program-yield-graph", forged_program_nodes, forged_program_edges, &.{});
    var forged_program_yield_report = program_backed_report;
    forged_program_yield_report.graph_fingerprint = forged_program_graph.fingerprint;
    forged_program_yield_report.report_fingerprint = forged_program_yield_report.computeFingerprint();
    const forged_program_yield_certificate = Evidence.BoundaryClosureCertificate.init(
        forged_program_yield_report,
        forged_program_graph,
        program_backed_policy,
        forged_program_refs[0..],
    );
    const forged_program_plans = [_]Evidence.BoundaryStaticTreatyPlan{ forged_yield_plan, nested_plan };
    try std.testing.expectError(
        error.BoundaryClosureCertificateMismatch,
        forged_program_yield_certificate.check(forged_program_graph, forged_program_yield_report, program_backed_policy, forged_program_plans[0..]),
    );
    const duplicate_yield_plan = Evidence.BoundaryStaticTreatyPlan.init(.{
        .label = program_backed_plan.label,
        .source_shape = shape,
        .selected_provider_offer_ref = offer.evidenceRef(),
        .selected_provider_ref = provider.evidenceRef(),
        .selected_capability_ref = capability.evidenceRef(),
        .selected_semantic_body = .boundary_program,
        .selected_provider_program_ref = program_backed_ref,
        .selected_provider_program_mapping_fingerprint = program_backed_plan.selected_provider_program_mapping_fingerprint,
        .selected_provider_program_request_mapping_tag = "payload_to_args",
        .selected_provider_program_result_mapping_tag = "result_to_resume",
        .selected_provider_program_effect_shape_count = 2,
        .selected_provider_program_effect_shape_fingerprint = Evidence.fingerprintBoundaryEffectShapeSet(&.{ nested_shape, nested_shape }),
    });
    const duplicate_yield_refs = [_]Evidence.Ref{ duplicate_yield_plan.evidenceRef(), nested_plan.evidenceRef() };
    const duplicate_yield_nodes = try allocator.dupe(Closure.Graph.Node, program_backed_nodes[0..]);
    defer allocator.free(duplicate_yield_nodes);
    for (duplicate_yield_nodes) |*node| {
        if (node.ref.eql(program_backed_plan.evidenceRef())) node.ref = duplicate_yield_plan.evidenceRef();
    }
    const duplicate_yield_edges = try allocator.alloc(Closure.Graph.Edge, program_backed_edges.len + 1);
    defer allocator.free(duplicate_yield_edges);
    @memcpy(duplicate_yield_edges[0..program_backed_edges.len], program_backed_edges[0..]);
    for (duplicate_yield_edges[0..program_backed_edges.len]) |*edge| {
        if (edge.to.eql(program_backed_plan.evidenceRef())) edge.to = duplicate_yield_plan.evidenceRef();
    }
    duplicate_yield_edges[program_backed_edges.len] = .{ .kind = .provider_program_yields, .from = program_backed_ref, .to = nested_shape.evidenceRef(), .label = "duplicate-provider-program-yield" };
    const duplicate_yield_graph = Closure.Graph.init("duplicate-provider-program-yield-graph", duplicate_yield_nodes, duplicate_yield_edges, &.{});
    var duplicate_yield_report = program_backed_report;
    duplicate_yield_report.graph_fingerprint = duplicate_yield_graph.fingerprint;
    duplicate_yield_report.report_fingerprint = duplicate_yield_report.computeFingerprint();
    const duplicate_yield_certificate = Evidence.BoundaryClosureCertificate.init(
        duplicate_yield_report,
        duplicate_yield_graph,
        program_backed_policy,
        duplicate_yield_refs[0..],
    );
    const duplicate_yield_plans = [_]Evidence.BoundaryStaticTreatyPlan{ duplicate_yield_plan, nested_plan };
    try std.testing.expectError(
        error.BoundaryClosureCertificateMismatch,
        duplicate_yield_certificate.check(duplicate_yield_graph, duplicate_yield_report, program_backed_policy, duplicate_yield_plans[0..]),
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
        mispaired_world_certificate.check(world_port_result.graph, mispaired_world_report, world_port_only_policy, world_port_result.static_treaty_plans),
    );
    const mismatched_world_pairs_report = Evidence.BoundaryClosureReport.init(.{
        .graph_fingerprint = world_port_result.graph.fingerprint,
        .effect_shape_count = 1,
        .closed_effect_shape_count = 0,
        .open_world_port_count = 1,
        .world_port_refs = world_port_result.report.world_port_refs,
        .policy_summary = world_port_only_policy.policySummary(),
    });
    const mismatched_world_pairs_certificate = Evidence.BoundaryClosureCertificate.init(
        mismatched_world_pairs_report,
        world_port_result.graph,
        world_port_only_policy,
        world_port_result.plan_refs,
    );
    try std.testing.expectError(
        error.BoundaryClosureCertificateMismatch,
        mismatched_world_pairs_certificate.check(world_port_result.graph, mismatched_world_pairs_report, world_port_only_policy, world_port_result.static_treaty_plans),
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
        omitted_intrinsic_certificate.check(world_port_result.graph, omitted_intrinsic_report, world_port_only_policy, world_port_result.static_treaty_plans),
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
        forged_intrinsic_certificate.check(result.graph, forged_intrinsic_report, closure_policy, result.static_treaty_plans),
    );
    const unattested_intrinsic_nodes = try allocator.alloc(Closure.Graph.Node, result.graph.nodes.len + 1);
    defer allocator.free(unattested_intrinsic_nodes);
    @memcpy(unattested_intrinsic_nodes[0..result.graph.nodes.len], result.graph.nodes);
    unattested_intrinsic_nodes[result.graph.nodes.len] = .{ .kind = .host_intrinsic, .ref = forged_intrinsic_ref, .label = "unattested-host-intrinsic" };
    const unattested_intrinsic_graph = Closure.Graph.init("unattested-host-intrinsic-ref", unattested_intrinsic_nodes, result.graph.edges, &.{});
    var unattested_intrinsic_report = forged_intrinsic_report;
    unattested_intrinsic_report.graph_fingerprint = unattested_intrinsic_graph.fingerprint;
    unattested_intrinsic_report.report_fingerprint = unattested_intrinsic_report.computeFingerprint();
    const unattested_intrinsic_certificate = Evidence.BoundaryClosureCertificate.init(
        unattested_intrinsic_report,
        unattested_intrinsic_graph,
        closure_policy,
        forged_plan_refs[0..],
    );
    try std.testing.expectError(
        error.BoundaryClosureCertificateMismatch,
        unattested_intrinsic_certificate.check(unattested_intrinsic_graph, unattested_intrinsic_report, closure_policy, result.static_treaty_plans),
    );
    const forged_unknown_refs = [_]Evidence.Ref{result.static_treaty_plans[0].source_shape.evidenceRef()};
    const undercounted_unknown_report = Evidence.BoundaryClosureReport.init(.{
        .graph_fingerprint = result.graph.fingerprint,
        .effect_shape_count = 1,
        .closed_effect_shape_count = 1,
        .unknown_body_count = 0,
        .unknown_refs = forged_unknown_refs[0..],
        .policy_summary = closure_policy.policySummary(),
    });
    const undercounted_unknown_certificate = Evidence.BoundaryClosureCertificate.init(
        undercounted_unknown_report,
        result.graph,
        closure_policy,
        forged_plan_refs[0..],
    );
    try std.testing.expectError(
        error.BoundaryClosureCertificateMismatch,
        undercounted_unknown_certificate.check(result.graph, undercounted_unknown_report, closure_policy, result.static_treaty_plans),
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
        error.BoundaryClosureCertificateMismatch,
        not_closed_certificate.check(result.graph, not_closed_report, closure_policy, result.static_treaty_plans),
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
    const missing_blocker_ref_certificate = Evidence.BoundaryClosureCertificate.initWithBlockerRefs(
        blocked_but_count_default_report,
        result.graph,
        closure_policy,
        forged_plan_refs[0..],
        &.{},
    );
    try std.testing.expectError(
        error.BoundaryClosureCertificateMismatch,
        missing_blocker_ref_certificate.check(result.graph, blocked_but_count_default_report, closure_policy, result.static_treaty_plans),
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
        blocked_but_count_default_certificate.check(result.graph, blocked_but_count_default_report, closure_policy, result.static_treaty_plans),
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
        empty_audit_result.static_treaty_plans,
    );
    const derived_empty_audit_certificate = Evidence.BoundaryClosureCertificate.init(
        empty_audit_result.report,
        empty_audit_result.graph,
        Evidence.BoundaryClosurePolicy.auditOnly(),
        empty_audit_result.plan_refs,
    );
    try derived_empty_audit_certificate.check(
        empty_audit_result.graph,
        empty_audit_result.report,
        Evidence.BoundaryClosurePolicy.auditOnly(),
        empty_audit_result.static_treaty_plans,
    );
    var mixed_allocator_buffer: [32768]u8 = undefined;
    var mixed_allocator_fba = std.heap.FixedBufferAllocator.init(&mixed_allocator_buffer);
    const mixed_owner_allocator = mixed_allocator_fba.allocator();
    var mixed_allocator_result = try Closure.analyze(allocator, .{
        .allocator = mixed_owner_allocator,
        .policy = Evidence.BoundaryClosurePolicy.auditOnly(),
    });
    try std.testing.expect(mixed_allocator_result.allocator.ptr == allocator.ptr);
    try std.testing.expect(mixed_allocator_result.allocator.vtable == allocator.vtable);
    mixed_allocator_result.deinit();

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
    try omitted_provider_shapes_result.certificate.check(omitted_provider_shapes_result.graph, omitted_provider_shapes_result.report, closure_policy, omitted_provider_shapes_result.static_treaty_plans);

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
    try provider_program_result.certificate.check(provider_program_result.graph, provider_program_result.report, closure_policy, provider_program_result.static_treaty_plans);

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
    try recursive_provider_program_result.certificate.check(recursive_provider_program_result.graph, recursive_provider_program_result.report, closure_policy, recursive_provider_program_result.static_treaty_plans);

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
    try depth_result.certificate.check(depth_result.graph, depth_result.report, depth_policy, depth_result.static_treaty_plans);

    const cycle_shape = Evidence.BoundaryEffectShape.init(.{
        .program_label = "cycle-root",
        .kind = .operation,
        .site_index = 0,
        .name = "cycle-request",
    });
    const cycle_shape_ref = cycle_shape.evidenceRef();
    const cycle_program_ref = Evidence.refFor(Evidence.domains.program_plan, 0xC1C1E, .{ .label = "cycle-provider-program" });
    const cycle_nested_shape = Evidence.BoundaryEffectShape.init(.{
        .program_label = "cycle-provider-program",
        .plan_hash = cycle_program_ref.fingerprint,
        .kind = .operation,
        .site_index = 1,
        .name = "cycle-nested-request",
    });
    const cycle_nested_shape_ref = cycle_nested_shape.evidenceRef();
    var cycle_shape_set_builder = Evidence.FingerprintBuilder.init(Evidence.domains.boundary_effect_shape);
    cycle_shape_set_builder.fieldUsize("shape_count", 1);
    cycle_shape_set_builder.fieldRef("shape", cycle_nested_shape_ref);
    const cycle_shape_set_fingerprint = cycle_shape_set_builder.finish();
    const cycle_provider_ref = Evidence.refFor(Evidence.domains.provider_manifest, 0xC1C1E1, .{ .label = "cycle-provider" });
    const cycle_offer_ref = Evidence.refFor(Evidence.domains.provider_offer, 0xC1C1E2, .{ .label = "cycle-offer" });
    const cycle_capability_ref = Evidence.refFor(Evidence.domains.capability, 0xC1C1E4, .{ .label = "cycle-capability" });
    const cycle_closure_blocker = Evidence.BoundaryClosureBlocker{
        .tag = .cycle_detected,
        .subject = cycle_program_ref,
        .summary = "selected provider program recurs through its own closure graph",
    };
    const cycle_plan = Evidence.BoundaryStaticTreatyPlan.init(.{
        .label = "cycle-plan",
        .source_shape = cycle_shape,
        .selected_semantic_body = .boundary_program,
        .selected_provider_ref = cycle_provider_ref,
        .selected_provider_offer_ref = cycle_offer_ref,
        .selected_capability_ref = cycle_capability_ref,
        .selected_provider_program_ref = cycle_program_ref,
        .selected_provider_program_mapping_fingerprint = 0xC1C1E3,
        .selected_provider_program_request_mapping_tag = "payload_to_args",
        .selected_provider_program_result_mapping_tag = "result_to_resume",
        .selected_provider_program_effect_shape_count = 1,
        .selected_provider_program_effect_shape_fingerprint = cycle_shape_set_fingerprint,
        .blockers = &.{cycle_closure_blocker},
    });
    const cycle_plan_ref = cycle_plan.evidenceRef();
    const cycle_mapping_ref = Evidence.refForProviderProgramMapping(cycle_plan.selected_provider_program_mapping_support_fingerprint.?);
    const cycle_nested_plan = Evidence.BoundaryStaticTreatyPlan.init(.{
        .label = "cycle-nested-plan",
        .source_shape = cycle_nested_shape,
        .selected_semantic_body = .boundary_program,
        .selected_provider_ref = cycle_provider_ref,
        .selected_provider_offer_ref = cycle_offer_ref,
        .selected_capability_ref = cycle_capability_ref,
        .selected_provider_program_ref = cycle_program_ref,
        .selected_provider_program_mapping_fingerprint = 0xC1C1E3,
        .selected_provider_program_request_mapping_tag = "payload_to_args",
        .selected_provider_program_result_mapping_tag = "result_to_resume",
        .selected_provider_program_effect_shape_count = 1,
        .selected_provider_program_effect_shape_fingerprint = cycle_shape_set_fingerprint,
        .blockers = &.{cycle_closure_blocker},
    });
    const cycle_nested_plan_ref = cycle_nested_plan.evidenceRef();
    const cycle_blocker = cycle_closure_blocker.toEvidenceBlocker();
    const cycle_blocker_ref = Evidence.refForBoundaryClosureBlocker(cycle_blocker);
    const cycle_nodes = [_]Evidence.BoundaryGraph.Node{
        .{ .kind = .operation_site, .ref = cycle_shape_ref, .label = "cycle shape" },
        .{ .kind = .operation_site, .ref = cycle_nested_shape_ref, .label = "cycle nested shape" },
        .{ .kind = .provider_manifest, .ref = cycle_provider_ref, .label = "cycle provider" },
        .{ .kind = .provider_offer, .ref = cycle_offer_ref, .label = "cycle offer" },
        .{ .kind = .capability_grant, .ref = cycle_capability_ref, .label = "cycle capability" },
        .{ .kind = .provider_program, .ref = cycle_program_ref, .label = "provider program" },
        .{ .kind = .provider_program_mapping, .ref = cycle_mapping_ref, .label = "provider program mapping" },
        .{ .kind = .treaty_shape_plan, .ref = cycle_plan_ref, .label = "static treaty plan" },
        .{ .kind = .treaty_shape_plan, .ref = cycle_nested_plan_ref, .label = "nested static treaty plan" },
        .{ .kind = .blocker, .ref = cycle_blocker_ref, .label = "cycle blocker" },
    };
    const cycle_edges = [_]Evidence.BoundaryGraph.Edge{
        .{ .kind = .treaty_planned, .from = cycle_shape_ref, .to = cycle_plan_ref },
        .{ .kind = .treaty_planned, .from = cycle_nested_shape_ref, .to = cycle_nested_plan_ref },
        .{ .kind = .handled_by_provider, .from = cycle_shape_ref, .to = cycle_offer_ref },
        .{ .kind = .handled_by_provider, .from = cycle_nested_shape_ref, .to = cycle_offer_ref },
        .{ .kind = .provider_advertises_offer, .from = cycle_provider_ref, .to = cycle_offer_ref },
        .{ .kind = .authorized_by_capability, .from = cycle_shape_ref, .to = cycle_capability_ref },
        .{ .kind = .authorized_by_capability, .from = cycle_nested_shape_ref, .to = cycle_capability_ref },
        .{ .kind = .provider_program_mapped_by, .from = cycle_program_ref, .to = cycle_mapping_ref },
        .{ .kind = .provider_program_yields, .from = cycle_program_ref, .to = cycle_nested_shape_ref },
        .{ .kind = .blocked_by, .from = cycle_program_ref, .to = cycle_blocker_ref },
    };
    const cycle_graph = Evidence.BoundaryGraph.init("provider-program-cycle-graph", cycle_nodes[0..], cycle_edges[0..], &.{});
    const cycle_policy = Evidence.BoundaryClosurePolicy.auditOnly();
    const cycle_report = Evidence.BoundaryClosureReport.init(.{
        .graph_fingerprint = cycle_graph.fingerprint,
        .provider_program_refs = &.{cycle_program_ref},
        .effect_shape_count = 2,
        .blockers = &.{cycle_blocker},
        .policy_summary = cycle_policy.policySummary(),
    });
    const cycle_certificate = Evidence.BoundaryClosureCertificate.init(
        cycle_report,
        cycle_graph,
        cycle_policy,
        &.{ cycle_plan_ref, cycle_nested_plan_ref },
    );
    try cycle_certificate.check(cycle_graph, cycle_report, cycle_policy, &.{ cycle_plan, cycle_nested_plan });

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
        node_bound_result.certificate.check(node_bound_result.graph, node_bound_result.report, node_bound_policy, node_bound_result.static_treaty_plans),
    );
}

test "boundary closure does not prove provider programs without nested shape witnesses" {
    const allocator = std.testing.allocator;
    const Closure = closure_source_program.BoundaryClosure;
    const root_shapes = Closure.effectShapesForProgram(closure_source_program, .operation);
    var catalog = try closure_harness.buildCatalog(allocator);
    defer catalog.deinit();
    var capability = try closure_source_program.Exchange.Capability.encode(allocator, .{
        .issuer_label = "closure-host",
        .provider_fingerprint = closure_harness.provider_fingerprint,
        .manifest_fingerprint = catalog.manifest.fingerprint,
        .allowed_request_kinds = .{ .operation = true },
        .allowed_operation_sites = &.{closure_approval_request.index},
        .allowed_protocol_op_fingerprints = &.{closure_approval_request.fingerprint},
        .allowed_requirement_labels = &.{"approval"},
        .allowed_op_names = &.{"request"},
    });
    defer capability.deinit();

    const provider_program_ref = closure_source_program.Evidence.refFor(
        closure_source_program.Evidence.domains.program_plan,
        closure_handler_program.compiled_plan.hash(),
        .{ .label = closure_handler_program.contract.label },
    );
    const provider_programs = [_]Closure.ProviderProgram{.{
        .provider_ref = catalog.provider_manifest.evidenceRef(),
        .program_ref = provider_program_ref,
        .provider_program_mapping_fingerprint = closure_approval_decl.provider_program_mapping_fingerprint,
        .provider_program_mapping_support_fingerprint = Closure.providerProgramMappingSupportFingerprintForSelection(catalog.provider_manifest.evidenceRef(), catalog.provider_offers[0].evidenceRef(), provider_program_ref, closure_approval_decl.provider_program_mapping_fingerprint, @intCast(catalog.provider_offers[0].provider_program_effect_shape_count.?), catalog.provider_offers[0].provider_program_effect_shape_fingerprint.?, .payload_to_args, .result_to_resume),
        .request_mapping = .payload_to_args,
        .result_mapping = .result_to_resume,
    }};
    var result = try Closure.analyze(allocator, .{
        .allocator = allocator,
        .root_shapes = root_shapes[0..1],
        .provider_programs = provider_programs[0..],
        .provider_manifests = &.{catalog.provider_manifest},
        .provider_offers = &.{catalog.provider_offers[0]},
        .capabilities = &.{capability},
        .policy = Closure.Policy.auditOnly(),
    });
    defer result.deinit();

    try std.testing.expect(!result.report.closed());
    try std.testing.expectEqual(@as(usize, 0), result.report.provider_program_refs.len);
    try std.testing.expectEqual(@as(usize, 0), result.certificate.provider_program_refs.len);
    var saw_nested_unknown = false;
    for (result.report.blockers) |blocker| {
        if (std.mem.eql(u8, blocker.tag, @tagName(Evidence.BoundaryClosureBlockerTag.provider_program_nested_unknown))) {
            saw_nested_unknown = true;
            try std.testing.expect(blocker.subject.?.eql(provider_program_ref));
        }
    }
    try std.testing.expect(saw_nested_unknown);
    for (result.graph.nodes) |node| {
        if (node.kind == .provider_program) try std.testing.expect(!node.ref.eql(provider_program_ref));
    }
    try result.certificate.check(result.graph, result.report, Closure.Policy.auditOnly(), result.static_treaty_plans);

    const RecursiveDecl = closure_source_program.Exchange.ProviderHandler.program(.{
        .label = "recursive-approval-program",
        .op = closure_approval_request,
        .program = closure_recursive_handler_program,
        .map_request = .payload_to_args,
        .map_result = .result_to_resume,
    });
    comptime @setEvalBranchQuota(10_000);
    const RecursiveHarness = closure_source_program.Exchange.ProviderHarness(.{
        .label = "recursive-approval-provider",
        .provider_fingerprint = @as(?u64, 0xC105E505),
        .entries = .{RecursiveDecl},
    });
    var recursive_catalog = try RecursiveHarness.buildCatalog(allocator);
    defer recursive_catalog.deinit();
    var recursive_capability = try closure_source_program.Exchange.Capability.encode(allocator, .{
        .issuer_label = "recursive-closure-host",
        .provider_fingerprint = RecursiveHarness.provider_fingerprint,
        .manifest_fingerprint = recursive_catalog.manifest.fingerprint,
        .allowed_request_kinds = .{ .operation = true },
        .allowed_operation_sites = &.{closure_approval_request.index},
        .allowed_protocol_op_fingerprints = &.{closure_approval_request.fingerprint},
        .allowed_requirement_labels = &.{"approval"},
        .allowed_op_names = &.{"request"},
    });
    defer recursive_capability.deinit();
    const recursive_shapes = closure_recursive_handler_program.BoundaryClosure.effectShapesForProgram(closure_recursive_handler_program, .operation);
    var stale_nested_shape = recursive_shapes[0];
    stale_nested_shape.name = "stale-nested-approval";
    try std.testing.expect(stale_nested_shape.fingerprint != stale_nested_shape.computeFingerprint());
    const stale_nested_shapes = [_]Closure.EffectShape{stale_nested_shape};
    const recursive_program_ref = closure_source_program.Evidence.refFor(
        closure_source_program.Evidence.domains.program_plan,
        closure_recursive_handler_program.compiled_plan.hash(),
        .{ .label = closure_recursive_handler_program.contract.label },
    );
    const stale_nested_programs = [_]Closure.ProviderProgram{.{
        .provider_ref = recursive_catalog.provider_manifest.evidenceRef(),
        .program_ref = recursive_program_ref,
        .provider_program_mapping_fingerprint = RecursiveDecl.provider_program_mapping_fingerprint,
        .provider_program_mapping_support_fingerprint = Closure.providerProgramMappingSupportFingerprintForSelection(recursive_catalog.provider_manifest.evidenceRef(), recursive_catalog.provider_offers[0].evidenceRef(), recursive_program_ref, RecursiveDecl.provider_program_mapping_fingerprint, @intCast(recursive_catalog.provider_offers[0].provider_program_effect_shape_count.?), recursive_catalog.provider_offers[0].provider_program_effect_shape_fingerprint.?, .payload_to_args, .result_to_resume),
        .request_mapping = .payload_to_args,
        .result_mapping = .result_to_resume,
        .shapes = stale_nested_shapes[0..],
    }};
    var stale_nested_result = try Closure.analyze(allocator, .{
        .allocator = allocator,
        .root_shapes = root_shapes[0..1],
        .provider_programs = stale_nested_programs[0..],
        .provider_manifests = &.{recursive_catalog.provider_manifest},
        .provider_offers = &.{recursive_catalog.provider_offers[0]},
        .capabilities = &.{recursive_capability},
        .policy = Closure.Policy.auditOnly(),
    });
    defer stale_nested_result.deinit();
    try std.testing.expect(!stale_nested_result.report.closed());
    try std.testing.expectEqual(@as(usize, 0), stale_nested_result.report.provider_program_refs.len);
    var saw_stale_contract_missing = false;
    for (stale_nested_result.report.blockers) |blocker| {
        if (std.mem.eql(u8, blocker.tag, @tagName(Evidence.BoundaryClosureBlockerTag.provider_program_contract_missing)) and
            blocker.subject != null and blocker.subject.?.eql(recursive_program_ref))
        {
            saw_stale_contract_missing = true;
        }
    }
    try std.testing.expect(saw_stale_contract_missing);
    try stale_nested_result.certificate.check(stale_nested_result.graph, stale_nested_result.report, Closure.Policy.auditOnly(), stale_nested_result.static_treaty_plans);
    try std.testing.expectEqual(error.BoundaryClosureNotClosed, stale_nested_result.assertClosed());

    var mappingless_provider = try closure_source_program.Exchange.ProviderManifest.encode(allocator, .{
        .label = "mappingless-program-provider",
        .provider_fingerprint = closure_harness.provider_fingerprint,
        .supported_program_manifest_fingerprints = &.{catalog.manifest.fingerprint},
        .supported_protocol_labels = &.{closure_approval_request.requirement_label},
        .supported_operation_sites = &.{closure_approval_request.index},
        .supported_protocol_op_fingerprints = &.{closure_approval_request.fingerprint},
    });
    defer mappingless_provider.deinit();
    const known_morphism = closure_source_program.Exchange.MorphismOffer{
        .label = "known-morphism-unknown-provider",
        .source_site_fingerprint = closure_approval_request.fingerprint,
        .source_protocol_op_fingerprint = closure_approval_request.fingerprint,
        .target_protocol_op_fingerprint = closure_approval_request.fingerprint,
        .pipeline_fingerprint = 0xC105E504,
        .source_response_refs = catalog.provider_offers[0].produced_response_refs,
        .target_response_refs = catalog.provider_offers[0].produced_response_refs,
    };
    var unknown_provider_morphism_result = try Closure.analyze(allocator, .{
        .allocator = allocator,
        .root_shapes = root_shapes[0..1],
        .provider_manifests = &.{mappingless_provider},
        .provider_offers = &.{catalog.provider_offers[0]},
        .morphism_offers = &.{known_morphism},
        .capabilities = &.{capability},
        .treaty_policy = .{ .allow_direct_handling = false },
        .policy = Closure.Policy.auditOnly(),
    });
    defer unknown_provider_morphism_result.deinit();
    try unknown_provider_morphism_result.assertClosed();
    try std.testing.expectEqual(@as(usize, 1), unknown_provider_morphism_result.report.unknown_body_count);
    try std.testing.expectEqual(@as(usize, 1), unknown_provider_morphism_result.report.unknown_refs.len);
    try std.testing.expectEqual(Evidence.SemanticBody.unknown, unknown_provider_morphism_result.static_treaty_plans[0].selected_semantic_body);
    try std.testing.expectEqual(Evidence.SemanticBody.pipeline, unknown_provider_morphism_result.static_treaty_plans[0].selected_morphism_semantic_body.?);
    try unknown_provider_morphism_result.certificate.check(
        unknown_provider_morphism_result.graph,
        unknown_provider_morphism_result.report,
        Closure.Policy.auditOnly(),
        unknown_provider_morphism_result.static_treaty_plans,
    );

    const mixed_provider_programs = [_]Closure.ProviderProgram{
        provider_programs[0],
        .{
            .provider_ref = catalog.provider_manifest.evidenceRef(),
            .program_ref = provider_program_ref,
            .provider_program_mapping_fingerprint = closure_approval_decl.provider_program_mapping_fingerprint,
            .provider_program_mapping_support_fingerprint = Closure.providerProgramMappingSupportFingerprintForSelection(catalog.provider_manifest.evidenceRef(), catalog.provider_offers[0].evidenceRef(), provider_program_ref, closure_approval_decl.provider_program_mapping_fingerprint, 0, Evidence.fingerprintBoundaryEffectShapeSet(&.{}), .payload_to_args, .result_to_resume),
            .request_mapping = .payload_to_args,
            .result_mapping = .result_to_resume,
            .effect_free = true,
        },
    };
    var mixed_result = try Closure.analyze(allocator, .{
        .allocator = allocator,
        .root_shapes = root_shapes[0..1],
        .provider_programs = mixed_provider_programs[0..],
        .provider_manifests = &.{catalog.provider_manifest},
        .provider_offers = &.{catalog.provider_offers[0]},
        .capabilities = &.{capability},
        .policy = Closure.Policy.auditOnly(),
    });
    defer mixed_result.deinit();

    try mixed_result.assertClosed();
    try std.testing.expectEqual(@as(usize, 1), mixed_result.report.provider_program_refs.len);
    try std.testing.expect(mixed_result.report.provider_program_refs[0].eql(provider_program_ref));
    for (mixed_result.report.blockers) |blocker| {
        try std.testing.expect(!std.mem.eql(u8, blocker.tag, @tagName(Evidence.BoundaryClosureBlockerTag.provider_program_nested_unknown)));
    }

    const source_program_ref = closure_source_program.Evidence.refFor(
        closure_source_program.Evidence.domains.program_plan,
        closure_source_program.compiled_plan.hash(),
        .{ .label = closure_source_program.contract.label },
    );
    var elaboration_policy = Closure.Policy.strict();
    elaboration_policy.require_root_program_refs = true;
    var elaborable_result = try Closure.analyze(allocator, .{
        .allocator = allocator,
        .root_shapes = root_shapes[0..1],
        .provider_programs = mixed_provider_programs[1..2],
        .provider_manifests = &.{catalog.provider_manifest},
        .provider_offers = &.{catalog.provider_offers[0]},
        .capabilities = &.{capability},
        .policy = elaboration_policy,
        .root_program_refs = &.{source_program_ref},
        .provider_harness_refs = &.{closure_source_program.Evidence.refForProviderHarness(closure_harness)},
    });
    defer elaborable_result.deinit();
    try elaborable_result.assertClosed();
    const elaboration_provider_programs = [_]Closure.ProviderProgram{.{
        .provider_ref = mixed_provider_programs[1].provider_ref,
        .program_ref = mixed_provider_programs[1].program_ref,
        .provider_program_mapping_fingerprint = mixed_provider_programs[1].provider_program_mapping_fingerprint,
        .provider_program_mapping_support_fingerprint = Closure.providerProgramMappingSupportFingerprintForPlan(elaborable_result.static_treaty_plans[0], .payload_to_args, .result_to_resume),
        .request_mapping = mixed_provider_programs[1].request_mapping,
        .result_mapping = mixed_provider_programs[1].result_mapping,
        .effect_free = mixed_provider_programs[1].effect_free,
    }};

    const Elaboration = Closure.Elaboration;
    var input_policy = Elaboration.Policy.strict();
    input_policy.closure_policy = elaboration_policy;
    const elaboration_input = Elaboration.Input{
        .closure_graph = elaborable_result.graph,
        .closure_report = elaborable_result.report,
        .closure_certificate = elaborable_result.certificate,
        .static_treaty_plans = elaborable_result.static_treaty_plans,
        .source_program_ref = source_program_ref,
        .provider_programs = elaboration_provider_programs[0..],
        .provider_harness_refs = &.{closure_source_program.Evidence.refForProviderHarness(closure_harness)},
        .policy = input_policy,
    };
    try elaboration_input.validate();
    const missing_effect_free_provider_programs = [_]Closure.ProviderProgram{.{
        .provider_ref = mixed_provider_programs[1].provider_ref,
        .program_ref = mixed_provider_programs[1].program_ref,
        .provider_program_mapping_fingerprint = mixed_provider_programs[1].provider_program_mapping_fingerprint,
        .provider_program_mapping_support_fingerprint = Closure.providerProgramMappingSupportFingerprintForPlan(elaborable_result.static_treaty_plans[0], .payload_to_args, .result_to_resume),
        .request_mapping = mixed_provider_programs[1].request_mapping,
        .result_mapping = mixed_provider_programs[1].result_mapping,
        .effect_free = false,
    }};
    var missing_effect_free_input = elaboration_input;
    missing_effect_free_input.provider_programs = missing_effect_free_provider_programs[0..];
    try std.testing.expectEqual(error.BoundaryElaborationProviderProgramRefMismatch, missing_effect_free_input.validate());
    var mismatched_root_input = elaboration_input;
    mismatched_root_input.source_program_ref = provider_program_ref;
    try std.testing.expectEqual(error.BoundaryElaborationRootRefMismatch, mismatched_root_input.validate());
    const wrong_provider_programs = [_]Closure.ProviderProgram{.{
        .provider_ref = catalog.provider_manifest.evidenceRef(),
        .program_ref = source_program_ref,
        .provider_program_mapping_fingerprint = closure_approval_decl.provider_program_mapping_fingerprint,
        .request_mapping = .payload_to_args,
        .result_mapping = .result_to_resume,
        .effect_free = true,
    }};
    var mismatched_provider_input = elaboration_input;
    mismatched_provider_input.provider_programs = wrong_provider_programs[0..];
    try std.testing.expectEqual(error.BoundaryElaborationProviderProgramRefMismatch, mismatched_provider_input.validate());
    const wrong_provider_ref_programs = [_]Closure.ProviderProgram{.{
        .provider_ref = source_program_ref,
        .program_ref = provider_program_ref,
        .provider_program_mapping_fingerprint = closure_approval_decl.provider_program_mapping_fingerprint,
        .request_mapping = .payload_to_args,
        .result_mapping = .result_to_resume,
        .effect_free = true,
    }};
    var mismatched_provider_ref_input = elaboration_input;
    mismatched_provider_ref_input.provider_programs = wrong_provider_ref_programs[0..];
    try std.testing.expectEqual(error.BoundaryElaborationProviderProgramRefMismatch, mismatched_provider_ref_input.validate());
    try mixed_result.certificate.check(mixed_result.graph, mixed_result.report, Closure.Policy.auditOnly(), mixed_result.static_treaty_plans);
}

test "boundary target normalization selects provider proofs and reports fallbacks" {
    const allocator = std.testing.allocator;
    const Closure = closure_source_program.BoundaryClosure;
    const Elaboration = Closure.Elaboration;
    const root_shapes = Closure.effectShapesForProgram(closure_source_program, .operation);
    var catalog = try closure_harness.buildCatalog(allocator);
    defer catalog.deinit();
    var capability = try closure_source_program.Exchange.Capability.encode(allocator, .{
        .issuer_label = "normalization-host",
        .provider_fingerprint = closure_harness.provider_fingerprint,
        .manifest_fingerprint = catalog.manifest.fingerprint,
        .allowed_request_kinds = .{ .operation = true },
        .allowed_operation_sites = &.{closure_approval_request.index},
        .allowed_protocol_op_fingerprints = &.{closure_approval_request.fingerprint},
        .allowed_requirement_labels = &.{"approval"},
        .allowed_op_names = &.{"request"},
    });
    defer capability.deinit();

    const source_program_ref = closure_source_program.Evidence.refFor(
        closure_source_program.Evidence.domains.program_plan,
        closure_source_program.compiled_plan.hash(),
        .{ .label = closure_source_program.contract.label },
    );
    const provider_program_ref = closure_source_program.Evidence.refFor(
        closure_source_program.Evidence.domains.program_plan,
        closure_handler_program.compiled_plan.hash(),
        .{ .label = closure_handler_program.contract.label },
    );
    const provider_programs = [_]Closure.ProviderProgram{.{
        .provider_ref = catalog.provider_manifest.evidenceRef(),
        .program_ref = provider_program_ref,
        .provider_program_mapping_fingerprint = closure_approval_decl.provider_program_mapping_fingerprint,
        .provider_program_mapping_support_fingerprint = Closure.providerProgramMappingSupportFingerprintForSelection(catalog.provider_manifest.evidenceRef(), catalog.provider_offers[0].evidenceRef(), provider_program_ref, closure_approval_decl.provider_program_mapping_fingerprint, 0, Evidence.fingerprintBoundaryEffectShapeSet(&.{}), .payload_to_args, .result_to_resume),
        .request_mapping = .payload_to_args,
        .result_mapping = .result_to_resume,
        .effect_free = true,
    }};
    var closure_policy = Closure.Policy.strict();
    closure_policy.require_root_program_refs = true;
    var result = try Closure.analyze(allocator, .{
        .allocator = allocator,
        .root_shapes = root_shapes[0..1],
        .provider_programs = provider_programs[0..],
        .provider_manifests = &.{catalog.provider_manifest},
        .provider_offers = &.{catalog.provider_offers[0]},
        .capabilities = &.{capability},
        .policy = closure_policy,
        .root_program_refs = &.{source_program_ref},
        .provider_harness_refs = &.{closure_source_program.Evidence.refForProviderHarness(closure_harness)},
    });
    defer result.deinit();
    try result.assertClosed();

    var elaboration_policy = Elaboration.Policy.strict();
    elaboration_policy.closure_policy = closure_policy;
    const input = Elaboration.Input{
        .closure_graph = result.graph,
        .closure_report = result.report,
        .closure_certificate = result.certificate,
        .static_treaty_plans = result.static_treaty_plans,
        .source_program_ref = source_program_ref,
        .provider_programs = provider_programs[0..],
        .provider_harness_refs = &.{closure_source_program.Evidence.refForProviderHarness(closure_harness)},
        .policy = elaboration_policy,
    };
    try input.validate();

    const provider_route = Elaboration.Target.Normalization.routeForPlan(input, result.static_treaty_plans[0]);
    try std.testing.expectEqual(Elaboration.Target.Normalization.RouteKind.provider_program, provider_route.kind);
    try std.testing.expectEqual(Elaboration.Target.Normalization.FallbackReason.none, provider_route.fallback_reason);
    const normalization_input = Elaboration.Target.Normalization.Input{
        .closure_certificate = result.certificate,
        .closure_graph = result.graph,
        .root_program_ref = source_program_ref,
        .provider_harness_refs = &.{closure_source_program.Evidence.refForProviderHarness(closure_harness)},
        .provider_programs = provider_programs[0..],
        .provider_program_refs = result.report.provider_program_refs,
        .static_treaty_plans = result.static_treaty_plans,
        .target_policy = Elaboration.Target.Policy.strictClosed(),
    };
    const provider_normalization_route = Elaboration.Target.Normalization.routeForPlan(normalization_input, result.static_treaty_plans[0]);
    try std.testing.expectEqual(Elaboration.Target.Normalization.RouteKind.provider_program, provider_normalization_route.kind);
    try std.testing.expectEqual(Elaboration.Target.Normalization.FallbackReason.none, provider_normalization_route.fallback_reason);
    const provider_selection = provider_route.provider_program orelse return error.ExpectedProviderProgramSelection;
    try std.testing.expect(provider_selection.provider_ref.eql(catalog.provider_manifest.evidenceRef()));
    try std.testing.expect(provider_selection.provider_offer_ref.eql(catalog.provider_offers[0].evidenceRef()));
    try std.testing.expect(provider_selection.program_ref.eql(provider_program_ref));
    try std.testing.expect(provider_selection.mapping_ref.eql(Evidence.refForProviderProgramMapping(result.static_treaty_plans[0].selected_provider_program_mapping_support_fingerprint.?)));
    try std.testing.expectEqual(@as(u64, 0), provider_selection.effect_shape_count);
    try std.testing.expectEqual(Evidence.fingerprintBoundaryEffectShapeSet(&.{}), provider_selection.effect_shape_fingerprint);

    var provider_forbidden_input = input;
    provider_forbidden_input.policy.allow_provider_program_linking = false;
    const provider_forbidden_route = Elaboration.Target.Normalization.routeForPlan(provider_forbidden_input, result.static_treaty_plans[0]);
    try std.testing.expectEqual(Elaboration.Target.Normalization.RouteKind.unsupported, provider_forbidden_route.kind);
    try std.testing.expectEqual(Elaboration.Target.Normalization.FallbackReason.provider_program_policy_rejected, provider_forbidden_route.fallback_reason);

    var missing_provider_input = input;
    missing_provider_input.provider_programs = &.{};
    const missing_provider_route = Elaboration.Target.Normalization.routeForPlan(missing_provider_input, result.static_treaty_plans[0]);
    try std.testing.expectEqual(Elaboration.Target.Normalization.RouteKind.unsupported, missing_provider_route.kind);
    try std.testing.expectEqual(Elaboration.Target.Normalization.FallbackReason.provider_program_proof_missing, missing_provider_route.fallback_reason);

    const declarative_plan = Closure.StaticTreatyPlan.init(.{
        .label = "normalization.declarative",
        .source_shape = root_shapes[0],
        .selected_semantic_body = .declarative,
    });
    var declarative_input = input;
    declarative_input.policy.require_program_backed_providers_for_internal_routes = false;
    const declarative_route = Elaboration.Target.Normalization.routeForPlan(declarative_input, declarative_plan);
    try std.testing.expectEqual(Elaboration.Target.Normalization.RouteKind.preserved, declarative_route.kind);
    try std.testing.expectEqual(Elaboration.Target.Normalization.FallbackReason.internal_route_preserved, declarative_route.fallback_reason);
    var declarative_forbidden_input = declarative_input;
    declarative_forbidden_input.policy.allow_declarative_morphisms = false;
    const declarative_forbidden_route = Elaboration.Target.Normalization.routeForPlan(declarative_forbidden_input, declarative_plan);
    try std.testing.expectEqual(Elaboration.Target.Normalization.RouteKind.unsupported, declarative_forbidden_route.kind);
    try std.testing.expectEqual(Elaboration.Target.Normalization.FallbackReason.route_policy_rejected, declarative_forbidden_route.fallback_reason);

    const intrinsic_ref = Evidence.refFor(Evidence.domains.host_intrinsic, 0x710C_A117, .{
        .label = "normalization.world",
        .kind_tag = @tagName(Evidence.HostIntrinsic.Kind.provider_function),
    });
    const world_plan = Closure.StaticTreatyPlan.init(.{
        .label = "normalization.world",
        .source_shape = root_shapes[0],
        .selected_semantic_body = .host_intrinsic,
        .selected_intrinsic_ref = intrinsic_ref,
        .host_intrinsic = true,
    });
    const world_port = Closure.WorldPort.init(.{
        .label = "normalization.world",
        .kind = .test_fixture,
        .effect_shape_ref = root_shapes[0].evidenceRef(),
        .exposed_intrinsic_ref = intrinsic_ref,
        .supported_protocol_labels = &.{"approval"},
        .supported_site_indexes = &.{closure_approval_request.index},
        .supported_protocol_op_fingerprints = &.{closure_approval_request.fingerprint},
    });
    var world_input = input;
    world_input.world_ports = &.{world_port};
    const strict_world_route = Elaboration.Target.Normalization.routeForPlan(world_input, world_plan);
    try std.testing.expectEqual(Elaboration.Target.Normalization.RouteKind.unsupported, strict_world_route.kind);
    world_input.policy.allow_world_ports = true;
    const intrinsic_forbidden_world_route = Elaboration.Target.Normalization.routeForPlan(world_input, world_plan);
    try std.testing.expectEqual(Elaboration.Target.Normalization.RouteKind.unsupported, intrinsic_forbidden_world_route.kind);
    try std.testing.expectEqual(Elaboration.Target.Normalization.FallbackReason.unsupported_semantic_body, intrinsic_forbidden_world_route.fallback_reason);
    world_input.policy.allow_intrinsic_world_ports = true;
    const world_route = Elaboration.Target.Normalization.routeForPlan(world_input, world_plan);
    try std.testing.expectEqual(Elaboration.Target.Normalization.RouteKind.world_port, world_route.kind);
    try std.testing.expectEqual(Elaboration.Target.Normalization.FallbackReason.world_port_selected, world_route.fallback_reason);
    try std.testing.expect(world_route.world_port.?.world_port_ref.eql(world_port.evidenceRef()));
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
