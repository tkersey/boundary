const std = @import("std");

/// Stable section ids for the generated formal core.
pub const SectionId = enum {
    atm_resume_transform,
    construction_coverage,
    direct_return,
    effect_mode_coverage,
    exception_effect,
    multi_prompt_separation,
    optional_resumption,
    performance_coverage,
    practical_witnesses,
    public_algebraic_builders,
    resource_bracketing,
    static_redelim,
    strict_effect_capabilities,
};

/// One generator-owned section in `FORMAL_CORE.md`.
pub const Section = struct {
    section_id: SectionId,
    title: []const u8,
    paragraphs: []const []const u8,
    witness_ids: []const []const u8 = &.{},
    example_ids: []const []const u8 = &.{},
    fixture_files: []const []const u8 = &.{},
};

const atm_paragraphs = [_][]const u8{
    "`atm_resume_transform` is the single-resume semantic witness behind the transform-style branch of the public lexical `shift.with(...)` story. The corresponding prompt protocol still exists in `src/frontend.zig` and `src/lowered_machine.zig`, but canonical docs now treat it as hidden implementation scaffolding rather than the root API.",
};

const direct_return_paragraphs = [_][]const u8{
    "`direct_return` is the abortive semantic witness behind lexical exception handling and abortive algebraic operations on `shift.with(...)`. The corresponding direct-return prompt protocol remains hidden implementation scaffolding in `src/frontend.zig` and `src/lowered_machine.zig`, not the canonical public story.",
};

const construction_paragraphs = [_][]const u8{
    "The public effect families are now expected to route through one shared internal construction substrate instead of embedding bespoke prompt-mode runner logic. `zig build effect-construction-boundary` is the explicit proof gate for that claim, and `shift.effect.writer` is the first proof family added entirely through the generalized path.",
};

const mode_coverage_paragraphs = [_][]const u8{
    "The shipped lexical/effect layer now covers each hidden internal control class explicitly:\n\n- transform-style (`.resume_then_transform` internally): `shift.effect.state`, `shift.effect.reader`, `shift.effect.resource`, `shift.effect.writer`\n- choice-style (`.resume_or_return` internally): `shift.effect.optional`\n- abortive (`.direct_return` internally): `shift.effect.exception`",
};

const exception_effect_paragraphs = [_][]const u8{
    "`shift.effect.exception.throw(Cap, ctx, payload)` gives the direct-return prompt mode a strict capability-checked family surface. The body tail does not resume after `throw`, and the catch policy converts the payload into the enclosing answer through `directReturn(payload)`.",
};

const optional_resumption_paragraphs = [_][]const u8{
    "`resume_or_return_return_now` and `resume_or_return_resume` are the zero-or-one-resume witnesses behind lexical optional handling and generated choice ops on `shift.with(...)`. Canonical docs now explain that behavior through `shift.effect.optional.request(Cap, ctx)`, generated choice handlers, and `shift.effect.choice.Decision`, while root `ResumeOrReturn` stays hidden helper machinery.",
};

const perf_coverage_paragraphs = [_][]const u8{
    "The checked performance surface now splits into two layers:\n\n- `bench-state-effect` / `bench-state-effect-check` for the deeper historical `state` lane\n- `bench-effect-matrix` / `bench-effect-matrix-check` for the `effect_family_matrix_v2` artifact covering `state_micro`, `reader_micro`, `reader_batch8`, `optional_return_now_micro`, `optional_return_now_prelude8`, `optional_resume_with_micro`, `optional_resume_with_batch8`, `exception_throw_micro`, `exception_throw_prelude8`, `algebraic_transform_micro`, `algebraic_choice_return_now_micro`, `algebraic_abort_micro`, `resource_normal_4`, `resource_normal_32`, `writer_micro`, `writer_batch16`, and `writer_batch64`",
    "The matrix classifies lanes as `micro`, `amortized`, or `investigation` so fixed-tax measurements, heavier representative bodies, and intentionally diagnostic loose-threshold lanes are not conflated.",
    "The current execution classes are `direct_frame` for `state`/`reader`, `abortive_control` for `optional`/`exception`, and `storage_backed` for `resource`/`writer`. The private decomposition benches (`bench-writer-decompose`, `bench-resource-decompose`, `bench-abortive-decompose`) are investigative tools for those classes and do not change the checked public artifact contract.",
};

const public_alg_builder_paragraphs = [_][]const u8{
    "`shift.algebraic` is the additive public builder surface for closed-world algebraic operations over the existing one-shot prompt runtime. It exposes `TransformOp`, `ChoiceOp`, `AbortOp`, `Program`, and the `handleTransform` / `handleChoice` / `handleAbort` builders without exporting a public continuation handle.",
    "The builder surface is currently proven by `zig build size-check`, `zig build compile-fail`, and exact-output examples instead of a separate benchmark artifact. The shipped witness examples are `examples/algebraic_artifact_search.zig` and `examples/algebraic_abortive_validation.zig`, and the compile-fail misuse fixtures cover duplicate op names, mixed or explicit mode mismatches, reserved generated names, and missing generated after-hooks.",
};

const static_redelim_paragraphs = [_][]const u8{
    "Nested prompts delimit statically: a `shift` reaches the nearest active prompt with the same prompt value, not a dynamically chosen ancestor. The live witness is `static_redelim`.",
};

const multi_prompt_paragraphs = [_][]const u8{
    "Distinct prompt values do not alias each other, even when they share the same handler protocol and answer types. The live witness is `multi_prompt`.",
};

const practical_witnesses_paragraphs = [_][]const u8{
    "The repo keeps one extra practical witness, `generator`, plus primary exact-output examples for `define_basic`, `early_exit`, `resume_or_return`, `front_door_workflow`, `nested_workflow`, `exception_basic`, `optional_basic`, `reader_basic`, `resource_basic`, `state_basic`, and `writer_basic`.",
    "The lowered proof engine is checked by `zig build backend-parity`. `src/parity_scenarios.zig` is the canonical lowered proof registry, `src/parity_kernel.zig` interprets it, and `src/parity_machine.zig` is only a facade over that kernel. The exact-output fixture artifacts are rendered from the same registry by `zig build proof-fixtures-write` and checked by `zig build proof-fixtures-check`. This remains hidden internal infrastructure beneath the canonical public `shift/reset` surface, not a public fallback runtime.",
};

const resource_bracketing_paragraphs = [_][]const u8{
    "`shift.effect.resource.acquire(Cap, ctx)` records acquired resources under a bracketed manager and guarantees LIFO cleanup after normal completion, outer `exception` abort, and outer `optional` return-now exits. Release errors are attempted for all acquired resources; the first release error becomes public only when no earlier body/reset error already won.",
};

const effect_capability_paragraphs = [_][]const u8{
    "The shipped additive families are `shift.effect.state`, `shift.effect.reader`, `shift.effect.optional`, `shift.effect.exception`, `shift.effect.resource`, and `shift.effect.writer`. They all rely on an exact private context type plus a fresh capability witness minted inside the family handler. Public operations are helper-based:\n\n- `shift.effect.state.get(Cap, ctx)` / `shift.effect.state.set(Cap, ctx, value)`\n- `shift.effect.reader.ask(Cap, ctx)`\n- `shift.effect.optional.request(Cap, ctx)`\n- `shift.effect.exception.throw(Cap, ctx, payload)`\n- `shift.effect.resource.acquire(Cap, ctx)`\n- `shift.effect.writer.tell(Cap, ctx, item)`",
    "`shift.effect.Define(.{ ... })` now lets users mint their own sealed transform, choice, and abort families on top of the same shared engine and exact-context boundary. Generated families export `Instance`, `computeProgram`, `handle`, `OpTag`, `definition`, `proof`, and `Op(.tag).perform(...)` / `Op(.tag).program(...)` helper surfaces without exposing raw contexts or public continuations. When installed through `shift.with(...)`, generated transform, choice, and abort families are projected as named lexical op fields such as `eff.<binding>.<op>.perform(...)` and `eff.<binding>.<op>.abort(...)`.",
    "Compile-fail fixtures under `test/compile_fail/` prove declaration-family mode/name invariants, optional and exception policy signatures, and resource manager shape checks.",
};

/// Canonical section registry used by the formal-core renderer.
pub const sections = [_]Section{
    .{
        .section_id = .atm_resume_transform,
        .title = "ATM Resume Transform",
        .paragraphs = &atm_paragraphs,
        .witness_ids = &.{"atm_resume_transform"},
    },
    .{
        .section_id = .construction_coverage,
        .title = "Construction Coverage",
        .paragraphs = &construction_paragraphs,
        .example_ids = &.{"writer_basic"},
    },
    .{
        .section_id = .direct_return,
        .title = "Direct Return",
        .paragraphs = &direct_return_paragraphs,
        .witness_ids = &.{"direct_return"},
    },
    .{
        .section_id = .effect_mode_coverage,
        .title = "Effect Mode Coverage",
        .paragraphs = &mode_coverage_paragraphs,
    },
    .{
        .section_id = .exception_effect,
        .title = "Exception Effect",
        .paragraphs = &exception_effect_paragraphs,
    },
    .{
        .section_id = .optional_resumption,
        .title = "Optional Resumption",
        .paragraphs = &optional_resumption_paragraphs,
        .witness_ids = &.{ "resume_or_return_return_now", "resume_or_return_resume" },
        .example_ids = &.{"optional_basic"},
    },
    .{
        .section_id = .performance_coverage,
        .title = "Performance Coverage",
        .paragraphs = &perf_coverage_paragraphs,
    },
    .{
        .section_id = .public_algebraic_builders,
        .title = "Public Algebraic Builders",
        .paragraphs = &public_alg_builder_paragraphs,
        .example_ids = &.{ "algebraic_artifact_search", "algebraic_abortive_validation" },
        .fixture_files = &.{
            "decl_family_duplicate_op_name_fails.zig",
            "decl_family_explicit_mode_mismatch_fails.zig",
            "decl_family_missing_after_hook_fails.zig",
            "decl_family_mixed_mode_fails.zig",
            "decl_family_reserved_name_fails.zig",
        },
    },
    .{
        .section_id = .static_redelim,
        .title = "Static Redelim",
        .paragraphs = &static_redelim_paragraphs,
        .witness_ids = &.{"static_redelim"},
    },
    .{
        .section_id = .multi_prompt_separation,
        .title = "Multi Prompt Separation",
        .paragraphs = &multi_prompt_paragraphs,
        .witness_ids = &.{"multi_prompt"},
    },
    .{
        .section_id = .practical_witnesses,
        .title = "Practical Witnesses",
        .paragraphs = &practical_witnesses_paragraphs,
        .witness_ids = &.{"generator"},
        .example_ids = &.{ "define_basic", "early_exit", "resume_or_return", "front_door_workflow", "nested_workflow", "exception_basic", "optional_basic", "reader_basic", "resource_basic", "state_basic", "writer_basic" },
    },
    .{
        .section_id = .resource_bracketing,
        .title = "Bracketed Resource Cleanup",
        .paragraphs = &resource_bracketing_paragraphs,
        .example_ids = &.{"resource_basic"},
    },
    .{
        .section_id = .strict_effect_capabilities,
        .title = "Strict Effect Capabilities",
        .paragraphs = &effect_capability_paragraphs,
        .fixture_files = &.{
            "decl_family_duplicate_op_name_fails.zig",
            "decl_family_explicit_mode_mismatch_fails.zig",
            "decl_family_missing_after_hook_fails.zig",
            "decl_family_mixed_mode_fails.zig",
            "decl_family_reserved_name_fails.zig",
            "exception_policy_missing_direct_return.zig",
            "exception_policy_wrong_direct_return_type.zig",
            "optional_policy_missing_resume_or_return.zig",
            "optional_policy_wrong_after_resume_type.zig",
            "resource_manager_missing_acquire.zig",
            "resource_manager_missing_release.zig",
            "resource_manager_wrong_release_type.zig",
        },
    },
};

/// Return the stable fragment id for one formal-core section.
pub fn anchorId(comptime id: SectionId) []const u8 {
    return switch (id) {
        .atm_resume_transform => "atm-resume-transform",
        .construction_coverage => "construction-coverage",
        .direct_return => "direct-return",
        .effect_mode_coverage => "effect-mode-coverage",
        .exception_effect => "exception-effect",
        .multi_prompt_separation => "multi-prompt-separation",
        .optional_resumption => "optional-resumption",
        .performance_coverage => "performance-coverage",
        .public_algebraic_builders => "public-algebraic-builders",
        .practical_witnesses => "practical-witnesses",
        .resource_bracketing => "resource-bracketing",
        .static_redelim => "static-redelim",
        .strict_effect_capabilities => "strict-effect-capabilities",
    };
}

/// Return the stable path+fragment used by semantic-manifest entries.
pub fn anchorPath(comptime id: SectionId) []const u8 {
    return switch (id) {
        .atm_resume_transform => "FORMAL_CORE.md#atm-resume-transform",
        .construction_coverage => "FORMAL_CORE.md#construction-coverage",
        .direct_return => "FORMAL_CORE.md#direct-return",
        .effect_mode_coverage => "FORMAL_CORE.md#effect-mode-coverage",
        .exception_effect => "FORMAL_CORE.md#exception-effect",
        .multi_prompt_separation => "FORMAL_CORE.md#multi-prompt-separation",
        .optional_resumption => "FORMAL_CORE.md#optional-resumption",
        .performance_coverage => "FORMAL_CORE.md#performance-coverage",
        .public_algebraic_builders => "FORMAL_CORE.md#public-algebraic-builders",
        .practical_witnesses => "FORMAL_CORE.md#practical-witnesses",
        .resource_bracketing => "FORMAL_CORE.md#resource-bracketing",
        .static_redelim => "FORMAL_CORE.md#static-redelim",
        .strict_effect_capabilities => "FORMAL_CORE.md#strict-effect-capabilities",
    };
}

/// Resolve one section entry by id.
pub fn sectionForId(comptime id: SectionId) Section {
    inline for (sections) |section| {
        if (section.section_id == id) return section;
    }
    unreachable;
}

/// Map a witness id to the formal-core section that owns its law anchor.
pub fn sectionForWitness(witness_id: []const u8) ?SectionId {
    if (std.mem.eql(u8, witness_id, "atm_resume_transform")) return .atm_resume_transform;
    if (std.mem.eql(u8, witness_id, "direct_return")) return .direct_return;
    if (std.mem.eql(u8, witness_id, "multi_prompt")) return .multi_prompt_separation;
    if (std.mem.eql(u8, witness_id, "resume_or_return_return_now")) return .optional_resumption;
    if (std.mem.eql(u8, witness_id, "resume_or_return_resume")) return .optional_resumption;
    if (std.mem.eql(u8, witness_id, "generator")) return .practical_witnesses;
    if (std.mem.eql(u8, witness_id, "static_redelim")) return .static_redelim;
    return null;
}
