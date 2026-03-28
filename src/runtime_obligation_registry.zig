/// Proof mode for one retained kernel-story surface.
/// The file path stays stable for build compatibility even though the old obligation ledger is gone.
pub const ProofMode = enum {
    compile_boundary,
    kernel_runtime,
};

/// One retained proof surface outside the case corpus artifact.
pub const Surface = struct {
    surface_id: []const u8,
    proof_surface: []const u8,
    proof_mode: ProofMode,
    source: []const u8,
    note: []const u8,
};

/// Generator-owned registry of retained kernel-story surfaces.
pub const surfaces = [_]Surface{
    .{
        .surface_id = "one_shot_survey.runtime_success",
        .proof_surface = "one_shot_survey",
        .proof_mode = .kernel_runtime,
        .source = "test/one_shot_survey/protocol_resume_transform_executes.zig",
        .note = "The runtime-positive survey fixture executes through the shared kernel runtime.",
    },
    .{
        .surface_id = "one_shot_survey.protocol_compile_shape",
        .proof_surface = "one_shot_survey",
        .proof_mode = .compile_boundary,
        .source = "build.zig",
        .note = "The remaining one-shot survey fixtures prove public protocol shape through build-zig-managed compile steps.",
    },
    .{
        .surface_id = "compile_fail.public_misuse",
        .proof_surface = "compile_fail",
        .proof_mode = .compile_boundary,
        .source = "build.zig",
        .note = "Compile-fail misuse fixtures run through build-zig-managed expected-compile-error steps.",
    },
    .{
        .surface_id = "size.prompt_shell_compact",
        .proof_surface = "size_check",
        .proof_mode = .compile_boundary,
        .source = "test/size_check.zig",
        .note = "Prompt shell compactness stays proven at the compile boundary rather than through a separate runtime lane.",
    },
};
