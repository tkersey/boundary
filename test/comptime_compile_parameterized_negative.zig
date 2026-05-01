const ability = @import("ability");
const ability_compile = @import("ability_compile");
const fixture = @import("ability_agent_vm_fixture_spec.zig");

const LoweredFixture = ability_compile.lowering_api.lowerAt(fixture.source_path, fixture.FixtureSpec);
const BasePlan = LoweredFixture.runtime_plan;
const parameterized_functions = blk: {
    var functions: [BasePlan.functions.len]ability_compile.lowering_api.FunctionPlan = BasePlan.functions[0..BasePlan.functions.len].*;
    for (BasePlan.functions, 0..) |function, index| {
        functions[index] = function;
    }
    functions[BasePlan.entry_index].parameter_count = 1;
    break :blk functions;
};

const ParameterizedPlan = blk: {
    var plan = BasePlan;
    plan.functions = &parameterized_functions;
    break :blk plan;
};

const CompiledParameterized = ability.compile(
    fixture.FixtureSpec.label,
    ParameterizedPlan,
    .{ .stable_build_fingerprint_seed = "ability-comptime-parameterized-negative" },
);

test "compile rejects parameterized artifact entries" {
    _ = CompiledParameterized;
}
