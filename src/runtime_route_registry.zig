/// Kernel proof lane for one retained proof case.
/// The file path stays stable for build compatibility even though route classification is gone.
pub const ProofLane = enum {
    private_lowered_runtime,
};

/// One retained kernel proof-case row.
pub const ProofCase = struct {
    case_id: []const u8,
    proof_lane: ProofLane,
    source: []const u8,
    note: []const u8,
};

/// Generator-owned kernel proof-case registry for the retained corpus.
pub const cases = [_]ProofCase{
    .{ .case_id = "atm_resume_transform", .proof_lane = .private_lowered_runtime, .source = "src/private_lowered_runtime.zig", .note = "Retained proof case executes through the private lowered kernel runtime." },
    .{ .case_id = "direct_return", .proof_lane = .private_lowered_runtime, .source = "src/private_lowered_runtime.zig", .note = "Retained proof case executes through the private lowered kernel runtime." },
    .{ .case_id = "multi_prompt", .proof_lane = .private_lowered_runtime, .source = "src/private_lowered_runtime.zig", .note = "Retained proof case executes through the private lowered kernel runtime." },
    .{ .case_id = "resume_or_return_resume", .proof_lane = .private_lowered_runtime, .source = "src/private_lowered_runtime.zig", .note = "Retained proof case executes through the private lowered kernel runtime." },
    .{ .case_id = "resume_or_return_return_now", .proof_lane = .private_lowered_runtime, .source = "src/private_lowered_runtime.zig", .note = "Retained proof case executes through the private lowered kernel runtime." },
    .{ .case_id = "static_redelim", .proof_lane = .private_lowered_runtime, .source = "src/private_lowered_runtime.zig", .note = "Retained proof case executes through the private lowered kernel runtime." },
    .{ .case_id = "early_exit", .proof_lane = .private_lowered_runtime, .source = "src/private_lowered_runtime.zig", .note = "Retained proof case executes through the private lowered kernel runtime." },
    .{ .case_id = "resume_or_return", .proof_lane = .private_lowered_runtime, .source = "src/private_lowered_runtime.zig", .note = "Retained proof case executes through the private lowered kernel runtime." },
    .{ .case_id = "nested_workflow", .proof_lane = .private_lowered_runtime, .source = "src/private_lowered_runtime.zig", .note = "Retained proof case executes through the private lowered kernel runtime." },
    .{ .case_id = "open_row_generator", .proof_lane = .private_lowered_runtime, .source = "src/private_lowered_runtime.zig", .note = "Retained proof case executes through the private lowered kernel runtime." },
    .{ .case_id = "state_basic", .proof_lane = .private_lowered_runtime, .source = "src/private_lowered_runtime.zig", .note = "Retained proof case executes through the private lowered kernel runtime." },
    .{ .case_id = "reader_basic", .proof_lane = .private_lowered_runtime, .source = "src/private_lowered_runtime.zig", .note = "Retained proof case executes through the private lowered kernel runtime." },
    .{ .case_id = "optional_basic", .proof_lane = .private_lowered_runtime, .source = "src/private_lowered_runtime.zig", .note = "Retained proof case executes through the private lowered kernel runtime." },
    .{ .case_id = "exception_basic", .proof_lane = .private_lowered_runtime, .source = "src/private_lowered_runtime.zig", .note = "Retained proof case executes through the private lowered kernel runtime." },
    .{ .case_id = "resource_basic", .proof_lane = .private_lowered_runtime, .source = "src/private_lowered_runtime.zig", .note = "Retained proof case executes through the private lowered kernel runtime." },
    .{ .case_id = "writer_basic", .proof_lane = .private_lowered_runtime, .source = "src/private_lowered_runtime.zig", .note = "Retained proof case executes through the private lowered kernel runtime." },
    .{ .case_id = "open_row_abortive_validation", .proof_lane = .private_lowered_runtime, .source = "src/private_lowered_runtime.zig", .note = "Retained proof case executes through the private lowered kernel runtime." },
    .{ .case_id = "open_row_artifact_search", .proof_lane = .private_lowered_runtime, .source = "src/private_lowered_runtime.zig", .note = "Retained proof case executes through the private lowered kernel runtime." },
};
