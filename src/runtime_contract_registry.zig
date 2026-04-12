/// One executable public-runtime contract case for the final lowered-runtime swap.
pub const Case = struct {
    case_id: []const u8,
    title: []const u8,
};

/// Current executable runtime-contract cases that still guard stackful-backed behavior.
pub const cases = [_]Case{
    .{ .case_id = "runtime_error.missing_prompt", .title = "Missing prompt still fails closed" },
    .{ .case_id = "runtime_error.cross_thread", .title = "Cross-thread runtime misuse still fails closed" },
    .{ .case_id = "runtime_error.runtime_busy", .title = "Runtime deinit rejects active reset" },
    .{ .case_id = "runtime_error.runtime_destroyed", .title = "Destroyed runtime rejects later use" },
    .{ .case_id = "runtime_error.non_diagonal_complete", .title = "Non-diagonal completion still fails closed" },
};
