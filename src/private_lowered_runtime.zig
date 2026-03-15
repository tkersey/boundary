const bridge_manifest = @import("direct_style_bridge_manifest");
const parity_kernel = @import("parity_kernel");
const parity_scenarios = @import("parity_scenarios");
const program_bridge = @import("program_bridge");

/// One lowered execution routed through the private runtime seam.
pub const Execution = struct {
    label: []const u8,
    scenario: *const parity_scenarios.Scenario,
};

/// Whether the private seam currently supports the given stable case id.
pub fn supportsCaseId(case_id: []const u8) bool {
    const case = bridge_manifest.find(case_id) orelse return false;
    return case.status == .supported;
}

/// Execute one supported bridge case through the private lowered runtime seam.
pub fn runCaseId(writer: anytype, case_id: []const u8) anyerror!Execution {
    const case = bridge_manifest.find(case_id) orelse return error.UnsupportedBridgeCase;
    if (case.status == .blocked) return error.UnsupportedBridgeCase;

    const scenario = parity_scenarios.byId(case.scenario_id);
    const state = parity_kernel.runScenario(case.scenario_id);
    try parity_kernel.writeTranscript(writer, &state);
    return .{
        .label = case.label,
        .scenario = scenario,
    };
}

/// Execute one supported direct-style bridge fixture through the private seam.
pub fn runBridgeFixture(comptime Fixture: type, writer: anytype) anyerror!Execution {
    const lowered = try program_bridge.lowerFixture(Fixture);
    const state = parity_kernel.runScenario(lowered.scenario.scenario_id);
    try parity_kernel.writeTranscript(writer, &state);
    return .{
        .label = lowered.label,
        .scenario = lowered.scenario,
    };
}
