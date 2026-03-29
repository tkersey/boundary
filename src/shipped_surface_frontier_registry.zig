/// Story position for one retained kernel-first surface.
/// The file path stays stable for build compatibility even though the old frontier ledger is gone.
pub const StoryPosition = enum {
    compile_boundary,
    kernel_runtime,
    source_validated_kernel,
};

/// One retained kernel-story surface record.
pub const Surface = struct {
    surface_id: []const u8,
    surface: []const u8,
    story_position: StoryPosition,
    source: []const u8,
    note: []const u8,
};

/// Generator-owned kernel-story truth for shipped and proof-facing surfaces.
pub const surfaces = [_]Surface{
    .{
        .surface_id = "root.public_kernel",
        .surface = "public_kernel",
        .story_position = .kernel_runtime,
        .source = "src/root.zig",
        .note = "The public root authors against one shared runtime kernel.",
    },
    .{
        .surface_id = "decl.public_families",
        .surface = "public_decl_families",
        .story_position = .kernel_runtime,
        .source = "src/program_api.zig",
        .note = "Public declaration families, including custom `shift.Decl.family(...)` declarations, lower into the shared runtime kernel.",
    },
    .{
        .surface_id = "decl.custom_families",
        .surface = "public_custom_families",
        .story_position = .kernel_runtime,
        .source = "src/program_api.zig",
        .note = "Public custom family declarations lower into the shared runtime kernel.",
    },
    .{
        .surface_id = "proof.kernel_case_corpus",
        .surface = "kernel_case_proof_corpus",
        .story_position = .kernel_runtime,
        .source = "src/private_lowered_runtime.zig",
        .note = "The retained case corpus executes through the shared runtime kernel.",
    },
    .{
        .surface_id = "proof.source_validated_corpus",
        .surface = "source_validated_proof_corpus",
        .story_position = .source_validated_kernel,
        .source = "src/source_lowering.zig",
        .note = "The internal source-validation corpus lowers repo-owned proof labels into canonical kernel scenarios.",
    },
    .{
        .surface_id = "compile_fail.public_misuse",
        .surface = "compile_fail",
        .story_position = .compile_boundary,
        .source = "build.zig",
        .note = "Compile-fail misuse fixtures prove public boundary and type-shape behavior through build-zig-managed compile checks.",
    },
    .{
        .surface_id = "one_shot_survey.runtime_success",
        .surface = "one_shot_survey",
        .story_position = .kernel_runtime,
        .source = "test/one_shot_survey/protocol_resume_transform_executes.zig",
        .note = "The runtime-success survey case executes through the shared runtime kernel.",
    },
};
