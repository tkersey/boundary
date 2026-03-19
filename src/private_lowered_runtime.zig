const lowered_machine = @import("lowered_machine");
const parity_scenarios = @import("parity_scenarios");
const program_bridge = @import("program_bridge");
const std = @import("std");

/// One lowered execution routed through the private runtime seam.
pub const Execution = struct {
    label: []const u8,
    scenario: *const parity_scenarios.Scenario,
};

/// Whether the private seam currently supports the given stable case id.
pub fn supportsCaseId(case_id: []const u8) bool {
    var lowered = program_bridge.lowerCaseId(std.heap.page_allocator, case_id) catch return false;
    defer lowered.deinit(std.heap.page_allocator);
    return lowered.status != .rejected;
}

/// Execute one supported bridge case through the private lowered runtime seam.
pub fn runCaseId(writer: anytype, case_id: []const u8) anyerror!Execution {
    var lowered = try program_bridge.lowerCaseId(std.heap.page_allocator, case_id);
    defer lowered.deinit(std.heap.page_allocator);
    if (lowered.status == .rejected) return error.RejectedBridgeCase;
    const scenario = parity_scenarios.byId(lowered.canonical_scenario_id.?);
    const state = lowered_machine.runSteps(scenario.steps);
    try lowered_machine.writeTranscript(writer, &state);
    return .{
        .label = lowered.label,
        .scenario = scenario,
    };
}

/// Execute one supported direct-style bridge fixture through the private seam.
pub fn runBridgeFixture(comptime Fixture: type, writer: anytype) anyerror!Execution {
    if (!@hasDecl(Fixture, "bridge_case_id")) {
        @compileError(@typeName(Fixture) ++ " must declare bridge_case_id");
    }
    var lowered = try program_bridge.lowerFixture(Fixture);
    defer lowered.deinit(std.heap.page_allocator);
    if (lowered.status == .rejected) return error.RejectedBridgeFixture;
    const scenario = parity_scenarios.byId(lowered.canonical_scenario_id.?);
    const state = lowered_machine.runSteps(lowered.steps);
    try lowered_machine.writeTranscript(writer, &state);
    return .{
        .label = lowered.label,
        .scenario = scenario,
    };
}
