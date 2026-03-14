const std = @import("std");

/// Stable section ids for the generated formal core.
pub const SectionId = enum {
    atm_resume_transform,
    direct_return,
    effect_mode_coverage,
    exception_effect,
    multi_prompt_separation,
    optional_resumption,
    practical_witnesses,
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
    "`shift.Prompt(.resume_then_transform, InAnswer, OutAnswer, ErrorSet)` selects a single-resume handler protocol with `resumeValue` and `afterResume`. The live semantic witness is `atm_resume_transform`, and the implementation path is the `resume_then_transform` arm in `src/raw.zig`.",
};

const direct_return_paragraphs = [_][]const u8{
    "`shift.Prompt(.direct_return, InAnswer, OutAnswer, ErrorSet)` selects the direct-completion protocol with `directReturn`. The live witness is `direct_return`, and the implementation path is the `direct_return` arm in `src/raw.zig`.",
};

const mode_coverage_paragraphs = [_][]const u8{
    "The shipped effect layer now covers each prompt mode explicitly:\n\n- `.resume_then_transform`: `shift.effect.state`, `shift.effect.reader`, `shift.effect.resource`\n- `.resume_or_return`: `shift.effect.optional`\n- `.direct_return`: `shift.effect.exception`",
};

const exception_effect_paragraphs = [_][]const u8{
    "`shift.effect.exception.throw(Cap, ctx, payload)` gives the direct-return prompt mode a strict capability-checked family surface. The body tail does not resume after `throw`, and the catch policy converts the payload into the enclosing answer through `directReturn(payload)`.",
};

const optional_resumption_paragraphs = [_][]const u8{
    "`shift.Prompt(.resume_or_return, InAnswer, OutAnswer, ErrorSet)` selects the zero-or-one-resume protocol with `resumeOrReturn` and `afterResume`. The live witnesses are `resume_or_return_return_now` and `resume_or_return_resume`, and the additive effect-family proof surface is `shift.effect.optional.request(Cap, ctx)` plus `examples/optional_basic.zig`.",
};

const static_redelim_paragraphs = [_][]const u8{
    "Nested prompts delimit statically: a `shift` reaches the nearest active prompt with the same prompt value, not a dynamically chosen ancestor. The live witness is `static_redelim`.",
};

const multi_prompt_paragraphs = [_][]const u8{
    "Distinct prompt values do not alias each other, even when they share the same handler protocol and answer types. The live witness is `multi_prompt`.",
};

const practical_witnesses_paragraphs = [_][]const u8{
    "The repo keeps one extra practical witness, `generator`, plus primary exact-output examples for `early_exit`, `resume_or_return`, `nested_workflow`, `exception_basic`, `optional_basic`, `reader_basic`, `resource_basic`, and `state_basic`.",
};

const resource_bracketing_paragraphs = [_][]const u8{
    "`shift.effect.resource.acquire(Cap, ctx)` records acquired resources under a bracketed manager and guarantees LIFO cleanup after normal completion, outer `exception` abort, and outer `optional` return-now exits. Release errors are attempted for all acquired resources; the first release error becomes public only when no earlier body/reset error already won.",
};

const effect_capability_paragraphs = [_][]const u8{
    "The shipped additive families are `shift.effect.state`, `shift.effect.reader`, `shift.effect.optional`, `shift.effect.exception`, and `shift.effect.resource`. They all rely on an exact private context type plus a fresh capability witness minted inside the family handler. Public operations are helper-based:\n\n- `shift.effect.state.get(Cap, ctx)` / `shift.effect.state.set(Cap, ctx, value)`\n- `shift.effect.reader.ask(Cap, ctx)`\n- `shift.effect.optional.request(Cap, ctx)`\n- `shift.effect.exception.throw(Cap, ctx, payload)`\n- `shift.effect.resource.acquire(Cap, ctx)`",
    "Forgery and cross-instance misuse are witnessed by compile-fail fixtures under `test/compile_fail/`.",
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
        .example_ids = &.{ "early_exit", "resume_or_return", "nested_workflow", "exception_basic", "optional_basic", "reader_basic", "resource_basic", "state_basic" },
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
            "effect_exception_forged_context_throw_fails.zig",
            "effect_exception_cross_instance_context_fails.zig",
            "effect_exception_catch_missing_direct_return.zig",
            "effect_exception_catch_wrong_direct_return_type.zig",
            "effect_resource_forged_context_acquire_fails.zig",
            "effect_resource_cross_instance_context_fails.zig",
            "effect_resource_manager_missing_acquire.zig",
            "effect_resource_manager_missing_release.zig",
            "effect_resource_manager_wrong_release_type.zig",
            "effect_state_forged_context_get_fails.zig",
            "effect_reader_forged_context_ask_fails.zig",
            "effect_optional_forged_context_request_fails.zig",
            "effect_state_cross_instance_context_fails.zig",
            "effect_reader_cross_instance_context_fails.zig",
            "effect_optional_cross_instance_context_fails.zig",
        },
    },
};

/// Return the stable fragment id for one formal-core section.
pub fn anchorId(comptime id: SectionId) []const u8 {
    return switch (id) {
        .atm_resume_transform => "atm-resume-transform",
        .direct_return => "direct-return",
        .effect_mode_coverage => "effect-mode-coverage",
        .exception_effect => "exception-effect",
        .multi_prompt_separation => "multi-prompt-separation",
        .optional_resumption => "optional-resumption",
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
        .direct_return => "FORMAL_CORE.md#direct-return",
        .effect_mode_coverage => "FORMAL_CORE.md#effect-mode-coverage",
        .exception_effect => "FORMAL_CORE.md#exception-effect",
        .multi_prompt_separation => "FORMAL_CORE.md#multi-prompt-separation",
        .optional_resumption => "FORMAL_CORE.md#optional-resumption",
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
