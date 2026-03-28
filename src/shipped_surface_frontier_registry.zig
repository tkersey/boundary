/// Current execution frontier for one public or proof-facing surface.
pub const Frontier = enum {
    compile_boundary,
    internal_adapter,
    kernel_runtime,
    reference_only,
    source_validated_kernel,
};

/// One shipped-surface frontier record.
pub const Surface = struct {
    surface_id: []const u8,
    surface: []const u8,
    frontier: Frontier,
    source: []const u8,
    note: []const u8,
};

/// Generator-owned frontier truth for shipped and proof-facing surfaces.
pub const surfaces = [_]Surface{
    .{
        .surface_id = "root.public_kernel",
        .surface = "public_kernel",
        .frontier = .kernel_runtime,
        .source = "src/root.zig",
        .note = "The public root authors against one shared runtime kernel.",
    },
    .{
        .surface_id = "decl.public_families",
        .surface = "public_decl_families",
        .frontier = .kernel_runtime,
        .source = "src/program_api.zig",
        .note = "Public declaration families, including custom `shift.Decl.family(...)` declarations, lower into the shared runtime kernel.",
    },
    .{
        .surface_id = "decl.custom_families",
        .surface = "public_custom_families",
        .frontier = .kernel_runtime,
        .source = "src/program_api.zig",
        .note = "Public custom family declarations lower into the shared runtime kernel.",
    },
    .{
        .surface_id = "proof.unchanged_body_corpus",
        .surface = "unchanged_body_proof_corpus",
        .frontier = .kernel_runtime,
        .source = "src/private_lowered_runtime.zig",
        .note = "The retained unchanged-body proof corpus executes through the shared runtime kernel.",
    },
    .{
        .surface_id = "proof.source_validated_corpus",
        .surface = "source_validated_proof_corpus",
        .frontier = .source_validated_kernel,
        .source = "src/source_lowering.zig",
        .note = "The internal source-validation corpus lowers repo-owned proof labels into canonical kernel scenarios.",
    },
    .{
        .surface_id = "compile_fail.public_misuse",
        .surface = "compile_fail",
        .frontier = .compile_boundary,
        .source = "build.zig",
        .note = "Compile-fail misuse fixtures prove public boundary and type-shape behavior through build-zig-managed compile checks.",
    },
    .{
        .surface_id = "one_shot_survey.runtime_success",
        .surface = "one_shot_survey",
        .frontier = .kernel_runtime,
        .source = "test/one_shot_survey/protocol_resume_transform_executes.zig",
        .note = "The runtime-success survey case executes through the shared runtime kernel.",
    },
    .{
        .surface_id = "frontend.internal_adapters",
        .surface = "internal_frontend_adapters",
        .frontier = .internal_adapter,
        .source = "src/program_frontend.zig",
        .note = "Internal frontend adapters lower retained proof labels into canonical kernel scenarios.",
    },
    .{
        .surface_id = "runtime.reference_stack_baseline",
        .surface = "reference_runtime",
        .frontier = .reference_only,
        .source = "src/runtime_stack_baseline.zig",
        .note = "The stack-runtime baseline is reference-only and not part of the published kernel story.",
    },
};
