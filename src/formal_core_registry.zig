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
    retired_surface_tombstones,
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
    "`atm_resume_transform` is the single-resume semantic witness behind one branch\nof the current public effects-library surface. The corresponding prompt\nprotocol still exists in `src/frontend.zig` and `src/lowered_machine.zig`, but\ncanonical docs treat those lower-level spellings as shared execution\nscaffolding rather than as the public product surface.",
};

const construction_paragraphs = [_][]const u8{
    "The public effects-library surface routes through one shared lowered runtime\nsubstrate instead of embedding bespoke runner logic per frontend. `zig build\neffect-construction-boundary` remains the explicit proof gate for that claim.",
};

const direct_return_paragraphs = [_][]const u8{
    "`direct_return` is the abortive semantic witness behind the current public\neffects-library surface's exception and abortive control behavior. The\ncorresponding prompt protocol remains hidden implementation scaffolding in\n`src/frontend.zig` and `src/lowered_machine.zig`, not a public root API.",
};

const mode_coverage_paragraphs = [_][]const u8{
    "The shipped surface exposes one effects-library surface backed by\ntransform-style, choice-style, and abortive internal control classes.\nFrontend builders still exercise those classes, but the docs treat them as\nadapters over the lowered runtime rather than as the product definition.",
};

const exception_effect_paragraphs = [_][]const u8{
    "Abortive exception behavior remains part of the lowered runtime kernel. Current\nfrontend adapters still model it with a fragment plus handler bridge, and\n`directReturn(payload)` remains the semantic hinge, but those adapter spellings\nare not the public product claim.",
};

const optional_resumption_paragraphs = [_][]const u8{
    "Optional resumption remains the zero-or-one resume branch of the lowered kernel.\nCurrent frontend adapters still expose the relevant request/policy shape, and\nthe canonical witnesses `resume_or_return_return_now` and\n`resume_or_return_resume` keep the one-shot continuation boundary explicit.",
};

const perf_coverage_paragraphs = [_][]const u8{
    "The checked performance surface now splits into two layers:\n\n- `bench-state-effect` / `bench-state-effect-check` for the deeper historical `state` lane\n- `bench-effect-matrix` / `bench-effect-matrix-check` for the `effect_family_matrix_v2` artifact covering `state_micro`, `reader_micro`, `reader_batch8`, `optional_return_now_micro`, `optional_return_now_prelude8`, `optional_resume_with_micro`, `optional_resume_with_batch8`, `exception_throw_micro`, `exception_throw_prelude8`, `writer_micro`, `writer_batch16`, and `writer_batch64`",
    "The matrix classifies lanes as `micro`, `amortized`, or `investigation` so fixed-tax measurements, heavier representative bodies, and intentionally diagnostic loose-threshold lanes are not conflated.",
    "The current execution classes are `direct_frame` for `state`/`reader`, `abortive_control` for `optional`/`exception`, and `storage_backed` for `writer`. The private decomposition benches (`bench-writer-decompose`, `bench-abortive-decompose`) are investigative tools for those classes and do not change the checked public artifact contract.",
};

const practical_witnesses_paragraphs = [_][]const u8{
    "The repo keeps one shipped checked state-writer walkthrough plus the lowered\nproof engine and exact-output fixture pipeline behind `zig build\nkernel-parity-check`, `zig build proof-fixtures-write`, and `zig build\nproof-fixtures-check`. Its retained proof id stays internal as\n`open_row_state_writer`, not as public product vocabulary.",
    "The lowered proof engine is checked by `zig build kernel-parity-check`.\n`src/parity_scenarios.zig` is the canonical lowered proof registry,\n`src/parity_kernel.zig` interprets it, and `src/parity_machine.zig` is only a\nfacade over that kernel. The exact-output fixture artifacts are rendered from\nthe same registry by `zig build proof-fixtures-write` and checked by `zig build\nproof-fixtures-check`. This remains hidden internal infrastructure beneath the\ncanonical public `shift/reset` surface, not a public fallback runtime.",
};

const algebraic_builder_paragraphs = [_][]const u8{
    "The old algebraic and generated-family root-builder surface is retired from the\nshipped package. Its remaining rows are tracked only as internal proof labels\nwhile the public docs stay centered on the root-level kernel.",
};

const retired_surface_paragraphs = [_][]const u8{
    "The retired root spellings are tombstoned by `public-root-contract-snapshot-check` and `public-error-api-ban`, and retired vocabulary stays out of proof-facing files through `retired-lane-inventory-check`.",
    "Legacy example ids, witness ids, and bridge ids remain proof-facing internal\nlabels; retired declaration-style and algebraic proof surfaces are no longer\npart of the public story.",
};

const resource_bracketing_paragraphs = [_][]const u8{
    "Bracketed resource cleanup remains part of the lowered runtime kernel. Current\nfrontend adapters still expose acquire/install manager hooks, acquired\nresources release in LIFO order, and outer exception or return-now exits still\ntrigger cleanup before they win publicly.",
    "Release errors are attempted for every acquired resource; the first release error becomes public only when no earlier body or reset error already won.",
};

const static_redelim_paragraphs = [_][]const u8{
    "Nested prompts delimit statically: a `shift` reaches the nearest active prompt with the same prompt value, not a dynamically chosen ancestor. The live witness is `static_redelim`.",
};

const multi_prompt_paragraphs = [_][]const u8{
    "Distinct prompt values do not alias each other, even when they share the same handler protocol and answer types. The live witness is `multi_prompt`.",
};

const effect_capability_paragraphs = [_][]const u8{
    "The active public surface is the effects-library layer: `shift.with(...)`,\n`shift.effect.*`, `shift.effect.Define(...)`, `shift.Runtime`, and\n`shift.RuntimeError`. Compile/lowering, executable-plan, and retained\ncompatibility mechanics remain internal engine layers beneath that public\nsurface rather than additional shipped fronts.",
    "Retired root spellings stay absent from the shipped surface and are checked by tombstone proofs instead of compatibility narratives.",
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
        .example_ids = &.{"open_row_state_writer"},
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
    },
    .{
        .section_id = .performance_coverage,
        .title = "Performance Coverage",
        .paragraphs = &perf_coverage_paragraphs,
    },
    .{
        .section_id = .practical_witnesses,
        .title = "Practical Witnesses",
        .paragraphs = &practical_witnesses_paragraphs,
        .example_ids = &.{"open_row_state_writer"},
    },
    .{
        .section_id = .public_algebraic_builders,
        .title = "Retired Algebraic Builders",
        .paragraphs = &algebraic_builder_paragraphs,
    },
    .{
        .section_id = .retired_surface_tombstones,
        .title = "Retired Surface Tombstones",
        .paragraphs = &retired_surface_paragraphs,
    },
    .{
        .section_id = .resource_bracketing,
        .title = "Bracketed Resource Cleanup",
        .paragraphs = &resource_bracketing_paragraphs,
        .example_ids = &.{"resource_basic"},
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
        .section_id = .strict_effect_capabilities,
        .title = "Strict Effect Capabilities",
        .paragraphs = &effect_capability_paragraphs,
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
        .practical_witnesses => "practical-witnesses",
        .public_algebraic_builders => "retired-algebraic-builders",
        .retired_surface_tombstones => "retired-surface-tombstones",
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
        .practical_witnesses => "FORMAL_CORE.md#practical-witnesses",
        .public_algebraic_builders => "FORMAL_CORE.md#retired-algebraic-builders",
        .retired_surface_tombstones => "FORMAL_CORE.md#retired-surface-tombstones",
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
    if (std.mem.eql(u8, witness_id, "static_redelim")) return .static_redelim;
    return null;
}
