const formal_core = @import("formal_core_registry");
const shipped_open_row_corpus = @import("shipped_open_row_corpus_registry");
const std = @import("std");

const canonical_note = "Canonical through the internal source-validated lowering corpus with direct-source and canonical-scenario parity proof.";
const open_row_frontend_note = "Canonical through the retained state-writer proof label plus the exact-output shipped example fixture proof.";
const witness_canonical_note = "Canonical through the retained witness proof corpus with source-validated lowering, canonical-scenario, evaluator, reference-machine, and runtime parity proof.";

/// Coverage category for the steady-state source-lowering proof surface.
pub const Category = enum {
    built_in_effect,
    example,
    user_defined_effect,
    witness,
};

/// Current coverage state for one source-lowering row.
pub const CoverageStatus = enum {
    covered,
    gap,
};

/// Lowering-kernel surface kind for one coverage-owned report row.
pub const LoweringSurface = enum {
    effect,
    example,
    source_case,
    user_defined_effect,
    witness,
};

/// One registry-owned lowering-kernel case consumed by reports.
pub const LoweringKernel = struct {
    case_id: []const u8,
    source_path: []const u8,
    entry_symbol: []const u8 = "run",
    surface: LoweringSurface,
};

/// One retained proof label or public-kernel lane covered by the internal source-lowering track.
pub const Row = struct {
    coverage_id: []const u8,
    category: Category,
    current_surface: []const u8,
    current_signal: []const u8,
    law_anchor: []const u8,
    source_label: []const u8,
    coverage_status: CoverageStatus = .gap,
    note: []const u8,
    lowering_rank: ?u16 = null,
    lowering_kernel: ?LoweringKernel = null,
};

fn customLawAnchor(kind: shipped_open_row_corpus.CustomExampleKind) []const u8 {
    return switch (kind) {
        .transform_basic, .choice_basic, .abort_basic => formal_core.anchorPath(.strict_effect_capabilities),
        .workflow, .abortive_validation, .artifact_search, .generator => formal_core.anchorPath(.practical_witnesses),
    };
}

fn customExampleRow(comptime row: shipped_open_row_corpus.CustomExample) Row {
    return .{
        .coverage_id = row.example_case_id,
        .category = .example,
        .current_surface = std.fmt.comptimePrint("proof.example.{s}", .{row.name}),
        .current_signal = std.fmt.comptimePrint("example_proof:{s}", .{row.fixture_name}),
        .law_anchor = customLawAnchor(row.kind),
        .source_label = std.fmt.comptimePrint("source.{s}", .{row.example_case_id}),
        .coverage_status = .covered,
        .note = canonical_note,
        .lowering_rank = switch (row.kind) {
            .transform_basic => 0,
            .choice_basic => 1,
            .abort_basic => 2,
            .workflow => 3,
            .abortive_validation => 4,
            .artifact_search => 5,
            .generator => 6,
        },
        .lowering_kernel = .{
            .case_id = row.example_case_id,
            .source_path = row.source_path,
            .surface = .example,
        },
    };
}

fn customUserDefinedRow(comptime row: shipped_open_row_corpus.CustomExample) ?Row {
    const user_defined_case_id = row.user_defined_case_id orelse return null;
    return .{
        .coverage_id = user_defined_case_id,
        .category = .user_defined_effect,
        .current_surface = std.fmt.comptimePrint("proof.{s}", .{user_defined_case_id}),
        .current_signal = std.fmt.comptimePrint("example_proof:{s}", .{row.fixture_name}),
        .law_anchor = formal_core.anchorPath(.strict_effect_capabilities),
        .source_label = std.fmt.comptimePrint("source.{s}", .{user_defined_case_id}),
        .coverage_status = .covered,
        .note = canonical_note,
        .lowering_rank = switch (row.kind) {
            .transform_basic => 7,
            .choice_basic => 8,
            .abort_basic => 9,
            else => unreachable,
        },
        .lowering_kernel = .{
            .case_id = user_defined_case_id,
            .source_path = row.source_path,
            .surface = .user_defined_effect,
        },
    };
}

fn builtInEffectRow(
    comptime coverage_id: []const u8,
    comptime current_surface: []const u8,
    comptime current_signal: []const u8,
    comptime law_anchor: []const u8,
    comptime source_label: []const u8,
) Row {
    return .{
        .coverage_id = coverage_id,
        .category = .built_in_effect,
        .current_surface = current_surface,
        .current_signal = current_signal,
        .law_anchor = law_anchor,
        .source_label = source_label,
        .coverage_status = .covered,
        .note = canonical_note,
    };
}

/// Generator-owned source-lowering coverage registry.
pub const rows = [_]Row{
    .{
        .coverage_id = "witness.atm_resume_transform",
        .category = .witness,
        .current_surface = "proof.witness.atm_resume_transform",
        .current_signal = "parity_scenarios:atm_resume_transform",
        .law_anchor = formal_core.anchorPath(.atm_resume_transform),
        .source_label = "source.witness.atm_resume_transform",
        .coverage_status = .covered,
        .note = witness_canonical_note,
        .lowering_rank = 19,
        .lowering_kernel = .{
            .case_id = "witness.atm_resume_transform",
            .source_path = "src/witness_sources.zig",
            .entry_symbol = "runAtmResumeTransform",
            .surface = .witness,
        },
    },
    .{
        .coverage_id = "witness.direct_return",
        .category = .witness,
        .current_surface = "proof.witness.direct_return",
        .current_signal = "parity_scenarios:direct_return",
        .law_anchor = formal_core.anchorPath(.direct_return),
        .source_label = "source.witness.direct_return",
        .coverage_status = .covered,
        .note = witness_canonical_note,
        .lowering_rank = 20,
        .lowering_kernel = .{
            .case_id = "witness.direct_return",
            .source_path = "src/witness_sources.zig",
            .entry_symbol = "runDirectReturn",
            .surface = .witness,
        },
    },
    .{
        .coverage_id = "witness.resume_or_return_return_now",
        .category = .witness,
        .current_surface = "proof.witness.resume_or_return_return_now",
        .current_signal = "parity_scenarios:resume_or_return_return_now",
        .law_anchor = formal_core.anchorPath(.optional_resumption),
        .source_label = "source.witness.resume_or_return_return_now",
        .coverage_status = .covered,
        .note = witness_canonical_note,
        .lowering_rank = 21,
        .lowering_kernel = .{
            .case_id = "witness.resume_or_return_return_now",
            .source_path = "src/witness_sources.zig",
            .entry_symbol = "runResumeOrReturnReturnNow",
            .surface = .witness,
        },
    },
    .{
        .coverage_id = "witness.resume_or_return_resume",
        .category = .witness,
        .current_surface = "proof.witness.resume_or_return_resume",
        .current_signal = "parity_scenarios:resume_or_return_resume",
        .law_anchor = formal_core.anchorPath(.optional_resumption),
        .source_label = "source.witness.resume_or_return_resume",
        .coverage_status = .covered,
        .note = witness_canonical_note,
        .lowering_rank = 22,
        .lowering_kernel = .{
            .case_id = "witness.resume_or_return_resume",
            .source_path = "src/witness_sources.zig",
            .entry_symbol = "runResumeOrReturnResume",
            .surface = .witness,
        },
    },
    .{
        .coverage_id = "witness.static_redelim",
        .category = .witness,
        .current_surface = "proof.witness.static_redelim",
        .current_signal = "parity_scenarios:static_redelim",
        .law_anchor = formal_core.anchorPath(.static_redelim),
        .source_label = "source.witness.static_redelim",
        .coverage_status = .covered,
        .note = witness_canonical_note,
        .lowering_rank = 23,
        .lowering_kernel = .{
            .case_id = "witness.static_redelim",
            .source_path = "src/witness_sources.zig",
            .entry_symbol = "runStaticRedelim",
            .surface = .witness,
        },
    },
    .{
        .coverage_id = "witness.multi_prompt",
        .category = .witness,
        .current_surface = "proof.witness.multi_prompt",
        .current_signal = "parity_scenarios:multi_prompt",
        .law_anchor = formal_core.anchorPath(.multi_prompt_separation),
        .source_label = "source.witness.multi_prompt",
        .coverage_status = .covered,
        .note = witness_canonical_note,
        .lowering_rank = 24,
        .lowering_kernel = .{
            .case_id = "witness.multi_prompt",
            .source_path = "src/witness_sources.zig",
            .entry_symbol = "runMultiPrompt",
            .surface = .witness,
        },
    },
    .{
        .coverage_id = "witness.generator",
        .category = .witness,
        .current_surface = "proof.witness.generator",
        .current_signal = "parity_scenarios:generator",
        .law_anchor = formal_core.anchorPath(.practical_witnesses),
        .source_label = "source.witness.generator",
        .coverage_status = .covered,
        .note = witness_canonical_note,
        .lowering_rank = 25,
        .lowering_kernel = .{
            .case_id = "witness.generator",
            .source_path = "src/witness_sources.zig",
            .entry_symbol = "runGenerator",
            .surface = .witness,
        },
    },
    .{
        .coverage_id = "example.early_exit",
        .category = .example,
        .current_surface = "proof.example.early_exit",
        .current_signal = "example_proof:early_exit.txt",
        .law_anchor = formal_core.anchorPath(.direct_return),
        .source_label = "source.example.early_exit",
        .coverage_status = .covered,
        .note = canonical_note,
        .lowering_rank = 10,
        .lowering_kernel = .{
            .case_id = "example.early_exit",
            .source_path = "examples/early_exit.zig",
            .surface = .example,
        },
    },
    .{
        .coverage_id = "example.resume_or_return",
        .category = .example,
        .current_surface = "proof.example.resume_or_return",
        .current_signal = "example_proof:resume_or_return.txt",
        .law_anchor = formal_core.anchorPath(.optional_resumption),
        .source_label = "source.example.resume_or_return",
        .coverage_status = .covered,
        .note = canonical_note,
        .lowering_rank = 11,
        .lowering_kernel = .{
            .case_id = "example.resume_or_return",
            .source_path = "examples/resume_or_return.zig",
            .surface = .example,
        },
    },
    .{
        .coverage_id = "example.nested_workflow",
        .category = .example,
        .current_surface = "proof.example.nested_workflow",
        .current_signal = "example_proof:nested_workflow.txt",
        .law_anchor = formal_core.anchorPath(.practical_witnesses),
        .source_label = "source.example.nested_workflow",
        .coverage_status = .covered,
        .note = canonical_note,
        .lowering_rank = 12,
        .lowering_kernel = .{
            .case_id = "example.nested_workflow",
            .source_path = "examples/nested_workflow.zig",
            .surface = .example,
        },
    },
    .{
        .coverage_id = "example.exception_basic",
        .category = .example,
        .current_surface = "proof.example.exception_basic",
        .current_signal = "example_proof:exception_basic.txt",
        .law_anchor = formal_core.anchorPath(.exception_effect),
        .source_label = "source.example.exception_basic",
        .coverage_status = .covered,
        .note = canonical_note,
        .lowering_rank = 16,
        .lowering_kernel = .{
            .case_id = "example.exception_basic",
            .source_path = "examples/exception_basic.zig",
            .surface = .example,
        },
    },
    .{
        .coverage_id = "example.optional_basic",
        .category = .example,
        .current_surface = "proof.example.optional_basic",
        .current_signal = "example_proof:optional_basic.txt",
        .law_anchor = formal_core.anchorPath(.optional_resumption),
        .source_label = "source.example.optional_basic",
        .coverage_status = .covered,
        .note = canonical_note,
        .lowering_rank = 15,
        .lowering_kernel = .{
            .case_id = "example.optional_basic",
            .source_path = "examples/optional_basic.zig",
            .surface = .example,
        },
    },
    .{
        .coverage_id = "example.reader_basic",
        .category = .example,
        .current_surface = "proof.example.reader_basic",
        .current_signal = "example_proof:reader_basic.txt",
        .law_anchor = formal_core.anchorPath(.strict_effect_capabilities),
        .source_label = "source.example.reader_basic",
        .coverage_status = .covered,
        .note = canonical_note,
        .lowering_rank = 14,
        .lowering_kernel = .{
            .case_id = "example.reader_basic",
            .source_path = "examples/reader_basic.zig",
            .surface = .example,
        },
    },
    .{
        .coverage_id = "example.resource_basic",
        .category = .example,
        .current_surface = "proof.example.resource_basic",
        .current_signal = "example_proof:resource_basic.txt",
        .law_anchor = formal_core.anchorPath(.resource_bracketing),
        .source_label = "source.example.resource_basic",
        .coverage_status = .covered,
        .note = canonical_note,
        .lowering_rank = 17,
        .lowering_kernel = .{
            .case_id = "example.resource_basic",
            .source_path = "examples/resource_basic.zig",
            .surface = .example,
        },
    },
    .{
        .coverage_id = "example.state_basic",
        .category = .example,
        .current_surface = "proof.example.state_basic",
        .current_signal = "example_proof:state_basic.txt",
        .law_anchor = formal_core.anchorPath(.strict_effect_capabilities),
        .source_label = "source.example.state_basic",
        .coverage_status = .covered,
        .note = canonical_note,
        .lowering_rank = 13,
        .lowering_kernel = .{
            .case_id = "example.state_basic",
            .source_path = "examples/state_basic.zig",
            .surface = .example,
        },
    },
    .{
        .coverage_id = "example.writer_basic",
        .category = .example,
        .current_surface = "proof.example.writer_basic",
        .current_signal = "example_proof:writer_basic.txt",
        .law_anchor = formal_core.anchorPath(.construction_coverage),
        .source_label = "source.example.writer_basic",
        .coverage_status = .covered,
        .note = canonical_note,
        .lowering_rank = 18,
        .lowering_kernel = .{
            .case_id = "example.writer_basic",
            .source_path = "examples/writer_basic.zig",
            .surface = .example,
        },
    },
    .{
        .coverage_id = "example.open_row_state_writer",
        .category = .example,
        .current_surface = "proof.example.open_row_state_writer",
        .current_signal = "example_proof:open_row_state_writer.txt",
        .law_anchor = formal_core.anchorPath(.construction_coverage),
        .source_label = "source.example.open_row_state_writer",
        .coverage_status = .covered,
        .note = open_row_frontend_note,
    },
    customExampleRow(shipped_open_row_corpus.custom_examples[0]),
    customExampleRow(shipped_open_row_corpus.custom_examples[1]),
    customExampleRow(shipped_open_row_corpus.custom_examples[2]),
    customExampleRow(shipped_open_row_corpus.custom_examples[3]),
    customExampleRow(shipped_open_row_corpus.custom_examples[4]),
    customExampleRow(shipped_open_row_corpus.custom_examples[5]),
    customExampleRow(shipped_open_row_corpus.custom_examples[6]),
    builtInEffectRow(
        "effect.state_basic",
        "proof.effect.state_basic",
        "example_proof:state_basic.txt",
        formal_core.anchorPath(.strict_effect_capabilities),
        "source.effect.state_basic",
    ),
    builtInEffectRow(
        "effect.reader_basic",
        "proof.effect.reader_basic",
        "example_proof:reader_basic.txt",
        formal_core.anchorPath(.strict_effect_capabilities),
        "source.effect.reader_basic",
    ),
    builtInEffectRow(
        "effect.optional_basic",
        "proof.effect.optional_basic",
        "example_proof:optional_basic.txt",
        formal_core.anchorPath(.optional_resumption),
        "source.effect.optional_basic",
    ),
    builtInEffectRow(
        "effect.exception_basic",
        "proof.effect.exception_basic",
        "example_proof:exception_basic.txt",
        formal_core.anchorPath(.exception_effect),
        "source.effect.exception_basic",
    ),
    builtInEffectRow(
        "effect.resource_basic",
        "proof.effect.resource_basic",
        "example_proof:resource_basic.txt",
        formal_core.anchorPath(.resource_bracketing),
        "source.effect.resource_basic",
    ),
    builtInEffectRow(
        "effect.writer_basic",
        "proof.effect.writer_basic",
        "example_proof:writer_basic.txt",
        formal_core.anchorPath(.construction_coverage),
        "source.effect.writer_basic",
    ),
    customUserDefinedRow(shipped_open_row_corpus.custom_examples[0]).?,
    customUserDefinedRow(shipped_open_row_corpus.custom_examples[1]).?,
    customUserDefinedRow(shipped_open_row_corpus.custom_examples[2]).?,
};

/// Find one source-lowering coverage row by stable id.
pub fn find(coverage_id: []const u8) ?*const Row {
    for (&rows) |*row| {
        if (std.mem.eql(u8, row.coverage_id, coverage_id)) return row;
    }
    return null;
}

/// Find one lowering-kernel case exposed through the coverage registry.
pub fn findLoweringKernelCase(case_id: []const u8) ?LoweringKernel {
    for (rows) |row| {
        const kernel = row.lowering_kernel orelse continue;
        if (std.mem.eql(u8, kernel.case_id, case_id)) return kernel;
    }
    return null;
}

/// Find one lowering-kernel case by its registry-owned report order.
pub fn findLoweringKernelByRank(rank: u16) ?LoweringKernel {
    for (rows) |row| {
        if (row.lowering_rank != rank) continue;
        return row.lowering_kernel;
    }
    return null;
}

fn hasCoverageId(comptime coverage_id: []const u8) bool {
    inline for (rows) |row| {
        if (comptime std.mem.eql(u8, row.coverage_id, coverage_id)) return true;
    }
    return false;
}

test "coverage registry keeps built-in effect rows" {
    try std.testing.expect(hasCoverageId("example.open_row_state_writer"));
    try std.testing.expect(hasCoverageId("effect.state_basic"));
    try std.testing.expect(hasCoverageId("effect.reader_basic"));
    try std.testing.expect(hasCoverageId("effect.optional_basic"));
    try std.testing.expect(hasCoverageId("effect.exception_basic"));
    try std.testing.expect(hasCoverageId("effect.resource_basic"));
    try std.testing.expect(hasCoverageId("effect.writer_basic"));
}

test "coverage registry exposes lowering-kernel rows only where source lowering is admitted" {
    const open_row_frontend = find("example.open_row_state_writer").?;
    try std.testing.expect(open_row_frontend.lowering_kernel == null);

    const open_row_example = findLoweringKernelCase("example.open_row_transform_basic").?;
    try std.testing.expectEqualStrings("examples/open_row_transform_basic.zig", open_row_example.source_path);
    try std.testing.expectEqual(LoweringSurface.example, open_row_example.surface);

    const witness = findLoweringKernelCase("witness.generator").?;
    try std.testing.expectEqualStrings("runGenerator", witness.entry_symbol);
    try std.testing.expectEqual(LoweringSurface.witness, witness.surface);

    const built_in_effect = find("effect.state_basic").?;
    try std.testing.expect(built_in_effect.lowering_kernel == null);

    const first_kernel = findLoweringKernelByRank(0).?;
    try std.testing.expectEqualStrings("example.open_row_transform_basic", first_kernel.case_id);
    const last_kernel = findLoweringKernelByRank(25).?;
    try std.testing.expectEqualStrings("witness.generator", last_kernel.case_id);
}
