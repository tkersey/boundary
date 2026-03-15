/// Current migration status for one public-runtime obligation.
pub const Status = enum {
    compat_noop_planned,
    compile_time_only,
    lowered_backend_ready,
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
        .status = .stack_backend_required,
        .source = "src/raw.zig",
        .note = "One-shot continuation reuse is still enforced by the stack runtime implementation.",
    },
    .{
        .obligation_id = "runtime_error.missing_prompt",
        .surface = "raw_runtime",
        .status = .stack_backend_required,
        .source = "src/raw.zig",
        .note = "Missing active prompt detection still comes from the stack runtime context.",
    },
    .{
        .obligation_id = "runtime_error.cross_thread",
        .surface = "raw_runtime",
        .status = .stack_backend_required,
        .source = "src/raw.zig",
        .note = "Thread-affinity checks still live in the stack runtime owner.",
    },
    .{
        .obligation_id = "runtime_error.runtime_destroyed",
        .surface = "raw_runtime",
        .status = .stack_backend_required,
        .source = "src/raw.zig",
        .note = "Destroyed-runtime misuse still depends on the stack runtime state machine.",
    },
    .{
        .obligation_id = "runtime_error.nested_non_diagonal_capture",
        .surface = "raw_runtime",
        .status = .stack_backend_required,
        .source = "src/raw.zig",
        .note = "Nested capture diagonality is still enforced by the stack runtime control engine.",
    },
    .{
        .obligation_id = "runtime_error.non_diagonal_complete",
        .surface = "raw_runtime",
        .status = .stack_backend_required,
        .source = "src/raw.zig",
        .note = "Non-diagonal completion is still guarded by the stack runtime implementation.",
    },
    .{
        .obligation_id = "one_shot_survey.protocol_runtime_success",
        .surface = "one_shot_survey",
        .status = .stack_backend_required,
        .source = "test/one_shot_survey/protocol_resume_transform_executes.zig",
        .note = "The runtime-positive survey fixture still executes the public stack runtime.",
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
        .status = .compat_noop_planned,
        .source = "test/size_check.zig",
        .note = "Runtime option fields still reflect stack-runtime defaults and need a compatibility story once the lowered backend is public.",
    },
    .{
        .obligation_id = "build.assembly_host_gate",
        .surface = "build_runtime",
        .status = .stack_backend_required,
        .source = "build.zig",
        .note = "Default build/test wiring still adds stack-switch assembly files for the shipped runtime path.",
    },
};
