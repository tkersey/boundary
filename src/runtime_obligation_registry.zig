/// Current migration status for one public-runtime obligation.
pub const Status = enum {
    compile_time_only,
    lowered_backend_ready,
    removed_from_shipped_path,
    stack_backend_required,
};

/// One public-runtime obligation outside the currently supported route-matrix corpus.
pub const Obligation = struct {
    obligation_id: []const u8,
    surface: []const u8,
    status: Status,
    source: []const u8,
    note: []const u8,
};

/// Generator-owned registry of remaining public-runtime obligations.
pub const obligations = [_]Obligation{
    .{
        .obligation_id = "one_shot_survey.protocol_runtime_success",
        .surface = "one_shot_survey",
        .status = .lowered_backend_ready,
        .source = "test/one_shot_survey/protocol_resume_transform_executes.zig",
        .note = "The runtime-positive survey fixture now executes through the lowered runtime seam instead of the raw stack runtime.",
    },
    .{
        .obligation_id = "one_shot_survey.protocol_compile_shape",
        .surface = "one_shot_survey",
        .status = .compile_time_only,
        .source = "build.zig",
        .note = "Most one-shot survey fixtures now prove public protocol shape through build-zig-managed compile steps rather than a shell harness.",
    },
    .{
        .obligation_id = "compile_fail.public_misuse",
        .surface = "compile_fail",
        .status = .compile_time_only,
        .source = "build.zig",
        .note = "Compile-fail misuse fixtures now run through build-zig-managed expected-compile-error steps rather than a shell harness.",
    },
    .{
        .obligation_id = "size.prompt_shell_compact",
        .surface = "size_check",
        .status = .compile_time_only,
        .source = "test/size_check.zig",
        .note = "Prompt shell compactness is already independent of the runtime backend.",
    },
    .{
        .obligation_id = "build.assembly_host_gate",
        .surface = "build_runtime",
        .status = .removed_from_shipped_path,
        .source = "build.zig",
        .note = "Default build/test wiring no longer adds stack-switch assembly files for the shipped or retained proof paths.",
    },
};
