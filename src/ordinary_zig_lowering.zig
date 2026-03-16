const ordinary = @import("ordinary_zig_registry");
const parity_scenarios = @import("parity_scenarios");
const program_frontend = @import("program_frontend");

/// Lower one supported ordinary-Zig fixture into the canonical scenario registry.
pub fn lowerFixture(comptime Fixture: type) error{UnsupportedOrdinaryCase}!program_frontend.LoweredProgram {
    if (!@hasDecl(Fixture, "ordinary_case_id")) {
        @compileError(@typeName(Fixture) ++ " must declare ordinary_case_id");
    }
    const case = ordinary.find(Fixture.ordinary_case_id) orelse return error.UnsupportedOrdinaryCase;
    return .{
        .label = case.label,
        .scenario = parity_scenarios.byId(case.scenario_id),
    };
}
