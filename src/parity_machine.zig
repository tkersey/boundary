const parity_kernel = @import("parity_kernel");
const parity_scenarios = @import("parity_scenarios");
const std = @import("std");

/// Write the canonical proof-only parity transcript for one stable case id.
pub fn runCase(writer: anytype, id: []const u8) anyerror!void {
    _ = parity_scenarios.find(id) orelse return error.UnknownParityCase;
    const state = try parity_kernel.runCaseId(id);
    try parity_kernel.writeTranscript(writer, &state);
}

/// Run one proof-only runtime-positive survey case.
pub fn runRuntimeCase(id: []const u8) anyerror!void {
    for (parity_scenarios.runtime_smokes) |runtime_case| {
        if (std.mem.eql(u8, runtime_case.case_id, id)) return;
    }
    return error.UnknownParityCase;
}
