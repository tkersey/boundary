const bridge_manifest = @import("direct_style_bridge_manifest");
const parity_scenarios = @import("parity_scenarios");
const program_frontend = @import("program_frontend");

/// Lower one supported unchanged direct-style fixture into the canonical scenario registry.
pub fn lowerFixture(comptime Fixture: type) error{UnsupportedBridgeCase}!program_frontend.LoweredProgram {
    if (!@hasDecl(Fixture, "bridge_case_id")) {
        @compileError(@typeName(Fixture) ++ " must declare bridge_case_id");
    }
    const case_id = Fixture.bridge_case_id;
    const case = bridge_manifest.find(case_id) orelse return error.UnsupportedBridgeCase;
    if (case.status == .blocked) return error.UnsupportedBridgeCase;
    return .{
        .label = case.label,
        .scenario = parity_scenarios.byId(case.scenario_id),
    };
}
