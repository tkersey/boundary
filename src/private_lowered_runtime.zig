const bridge_manifest = @import("direct_style_bridge_manifest");
const lowered_machine = @import("lowered_machine");
const parity_scenarios = @import("parity_scenarios");

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
    const state = lowered_machine.runSteps(scenario.steps);
    try lowered_machine.writeTranscript(writer, &state);
    return .{
        .label = case.label,
        .scenario = scenario,
    };
}

/// Execute one supported direct-style bridge fixture through the private seam.
pub fn runBridgeFixture(comptime Fixture: type, writer: anytype) anyerror!Execution {
    if (!@hasDecl(Fixture, "bridge_case_id")) {
        @compileError(@typeName(Fixture) ++ " must declare bridge_case_id");
    }
    return runCaseId(writer, Fixture.bridge_case_id);
}
