/// Execution route classification for one retained proof case.
pub const Route = enum {
    kernel_runtime,
    scenario_replay,
};

/// One route-matrix entry for the retained proof corpus.
pub const Case = struct {
    case_id: []const u8,
    route: Route,
    source: []const u8,
    note: []const u8,
};

/// Generator-owned route registry for the retained proof corpus.
pub const cases = [_]Case{
    .{ .case_id = "atm_resume_transform", .route = .kernel_runtime, .source = "src/private_lowered_runtime.zig", .note = "retained proof case executes through kernel_runtime" },
    .{ .case_id = "direct_return", .route = .kernel_runtime, .source = "src/private_lowered_runtime.zig", .note = "retained proof case executes through kernel_runtime" },
    .{ .case_id = "multi_prompt", .route = .kernel_runtime, .source = "src/private_lowered_runtime.zig", .note = "retained proof case executes through kernel_runtime" },
    .{ .case_id = "resume_or_return_resume", .route = .kernel_runtime, .source = "src/private_lowered_runtime.zig", .note = "retained proof case executes through kernel_runtime" },
    .{ .case_id = "resume_or_return_return_now", .route = .kernel_runtime, .source = "src/private_lowered_runtime.zig", .note = "retained proof case executes through kernel_runtime" },
    .{ .case_id = "static_redelim", .route = .kernel_runtime, .source = "src/private_lowered_runtime.zig", .note = "retained proof case executes through kernel_runtime" },
    .{ .case_id = "early_exit", .route = .kernel_runtime, .source = "src/private_lowered_runtime.zig", .note = "retained proof case executes through kernel_runtime" },
    .{ .case_id = "resume_or_return", .route = .kernel_runtime, .source = "src/private_lowered_runtime.zig", .note = "retained proof case executes through kernel_runtime" },
    .{ .case_id = "nested_workflow", .route = .kernel_runtime, .source = "src/private_lowered_runtime.zig", .note = "retained proof case executes through kernel_runtime" },
    .{ .case_id = "open_row_generator", .route = .kernel_runtime, .source = "src/private_lowered_runtime.zig", .note = "retained proof case executes through kernel_runtime" },
    .{ .case_id = "state_basic", .route = .kernel_runtime, .source = "src/private_lowered_runtime.zig", .note = "retained proof case executes through kernel_runtime" },
    .{ .case_id = "reader_basic", .route = .kernel_runtime, .source = "src/private_lowered_runtime.zig", .note = "retained proof case executes through kernel_runtime" },
    .{ .case_id = "optional_basic", .route = .kernel_runtime, .source = "src/private_lowered_runtime.zig", .note = "retained proof case executes through kernel_runtime" },
    .{ .case_id = "exception_basic", .route = .kernel_runtime, .source = "src/private_lowered_runtime.zig", .note = "retained proof case executes through kernel_runtime" },
    .{ .case_id = "resource_basic", .route = .kernel_runtime, .source = "src/private_lowered_runtime.zig", .note = "retained proof case executes through kernel_runtime" },
    .{ .case_id = "writer_basic", .route = .kernel_runtime, .source = "src/private_lowered_runtime.zig", .note = "retained proof case executes through kernel_runtime" },
    .{ .case_id = "open_row_abortive_validation", .route = .kernel_runtime, .source = "src/private_lowered_runtime.zig", .note = "retained proof case executes through kernel_runtime" },
    .{ .case_id = "open_row_artifact_search", .route = .kernel_runtime, .source = "src/private_lowered_runtime.zig", .note = "retained proof case executes through kernel_runtime" },
};
