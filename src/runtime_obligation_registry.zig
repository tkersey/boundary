/// Current migration status for one public-runtime obligation.
pub const Status = enum {
    compat_noop_landed,
    compat_noop_planned,
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
        .obligation_id = "runtime_error.already_resolved",
        .surface = "raw_runtime",
        .status = .removed_from_shipped_path,
        .source = "src/raw.zig",
        .note = "Already-resolved continuation misuse remains compat/raw-only and is no longer part of the shipped runtime path.",
    },
    .{
        .obligation_id = "runtime_error.missing_prompt",
        .surface = "raw_runtime",
        .status = .removed_from_shipped_path,
        .source = "src/raw.zig",
        .note = "Missing prompt detection is now enforced by the canonical frontend/runtime path and the old raw implementation is compat-only.",
    },
    .{
        .obligation_id = "runtime_error.cross_thread",
        .surface = "raw_runtime",
        .status = .removed_from_shipped_path,
        .source = "src/raw.zig",
        .note = "Cross-thread misuse remains surfaced by the canonical runtime wrapper and the old raw implementation is compat-only.",
    },
    .{
        .obligation_id = "runtime_error.runtime_destroyed",
        .surface = "raw_runtime",
        .status = .removed_from_shipped_path,
        .source = "src/raw.zig",
        .note = "Destroyed-runtime misuse remains surfaced by the canonical runtime wrapper and the old raw implementation is compat-only.",
    },
    .{
        .obligation_id = "runtime_error.nested_non_diagonal_capture",
        .surface = "raw_runtime",
        .status = .removed_from_shipped_path,
        .source = "src/raw.zig",
        .note = "Nested capture diagonality remains a compat/raw-only concern and is no longer part of the shipped runtime path.",
    },
    .{
        .obligation_id = "runtime_error.non_diagonal_complete",
        .surface = "raw_runtime",
        .status = .removed_from_shipped_path,
        .source = "src/raw.zig",
        .note = "Non-diagonal completion is now enforced by the canonical frontend/runtime path and the old raw implementation is compat-only.",
    },
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
        .source = "test/one_shot_survey/run.sh",
        .note = "Most one-shot survey fixtures prove public protocol shape at compile time only.",
    },
    .{
        .obligation_id = "compile_fail.public_misuse",
        .surface = "compile_fail",
        .status = .compile_time_only,
        .source = "test/compile_fail/run.sh",
        .note = "Compile-fail misuse fixtures already target public API and type-shape constraints rather than runtime execution.",
    },
    .{
        .obligation_id = "size.prompt_shell_compact",
        .surface = "size_check",
        .status = .compile_time_only,
        .source = "test/size_check.zig",
        .note = "Prompt shell compactness is already independent of the runtime backend.",
    },
    .{
        .obligation_id = "size.runtime_options_compat",
        .surface = "size_check",
        .status = .compat_noop_landed,
        .source = "src/raw.zig",
        .note = "Runtime option fields remain source-visible compatibility fields even though stack sizing now uses internal defaults.",
    },
    .{
        .obligation_id = "build.assembly_host_gate",
        .surface = "build_runtime",
        .status = .removed_from_shipped_path,
        .source = "build.zig",
        .note = "Default build/test wiring no longer adds stack-switch assembly files for the shipped runtime path.",
    },
};
