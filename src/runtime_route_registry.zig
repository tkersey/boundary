/// Execution route classification for one supported runtime case.
pub const Route = enum {
    lowered_machine,
    scenario_replay,
};

/// One route-matrix entry for the supported runtime corpus.
pub const Case = struct {
    case_id: []const u8,
    route: Route,
    source: []const u8,
    note: []const u8,
};

/// Generator-owned route registry for the currently supported runtime corpus.
pub const cases = [_]Case{
    .{ .case_id = "atm_resume_transform", .route = .lowered_machine, .source = "src/private_lowered_runtime.zig", .note = "supported bridge case executes through lowered_machine" },
    .{ .case_id = "direct_return", .route = .lowered_machine, .source = "src/private_lowered_runtime.zig", .note = "supported bridge case executes through lowered_machine" },
    .{ .case_id = "multi_prompt", .route = .lowered_machine, .source = "src/private_lowered_runtime.zig", .note = "supported bridge case executes through lowered_machine" },
    .{ .case_id = "resume_or_return_resume", .route = .lowered_machine, .source = "src/private_lowered_runtime.zig", .note = "supported bridge case executes through lowered_machine" },
    .{ .case_id = "resume_or_return_return_now", .route = .lowered_machine, .source = "src/private_lowered_runtime.zig", .note = "supported bridge case executes through lowered_machine" },
    .{ .case_id = "static_redelim", .route = .lowered_machine, .source = "src/private_lowered_runtime.zig", .note = "supported bridge case executes through lowered_machine" },
    .{ .case_id = "early_exit", .route = .lowered_machine, .source = "src/private_lowered_runtime.zig", .note = "supported bridge case executes through lowered_machine" },
    .{ .case_id = "resume_or_return", .route = .lowered_machine, .source = "src/private_lowered_runtime.zig", .note = "supported bridge case executes through lowered_machine" },
    .{ .case_id = "nested_workflow", .route = .lowered_machine, .source = "src/private_lowered_runtime.zig", .note = "supported bridge case executes through lowered_machine" },
    .{ .case_id = "generator", .route = .lowered_machine, .source = "src/private_lowered_runtime.zig", .note = "supported bridge case executes through lowered_machine" },
    .{ .case_id = "state_basic", .route = .lowered_machine, .source = "src/private_lowered_runtime.zig", .note = "supported bridge case executes through lowered_machine" },
    .{ .case_id = "reader_basic", .route = .lowered_machine, .source = "src/private_lowered_runtime.zig", .note = "supported bridge case executes through lowered_machine" },
    .{ .case_id = "optional_basic", .route = .lowered_machine, .source = "src/private_lowered_runtime.zig", .note = "supported bridge case executes through lowered_machine" },
    .{ .case_id = "exception_basic", .route = .lowered_machine, .source = "src/private_lowered_runtime.zig", .note = "supported bridge case executes through lowered_machine" },
    .{ .case_id = "resource_basic", .route = .lowered_machine, .source = "src/private_lowered_runtime.zig", .note = "supported bridge case executes through lowered_machine" },
    .{ .case_id = "writer_basic", .route = .lowered_machine, .source = "src/private_lowered_runtime.zig", .note = "supported bridge case executes through lowered_machine" },
    .{ .case_id = "algebraic_abortive_validation", .route = .lowered_machine, .source = "src/private_lowered_runtime.zig", .note = "supported bridge case executes through lowered_machine" },
    .{ .case_id = "algebraic_artifact_search", .route = .lowered_machine, .source = "src/private_lowered_runtime.zig", .note = "supported bridge case executes through lowered_machine" },
};
