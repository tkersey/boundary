const ability = @import("ability");
const ability_compile = @import("ability_compile");
const fixture = @import("ability_agent_vm_fixture_spec.zig");

const LoweredFixture = ability_compile.lowering_api.lowerAt(fixture.source_path, fixture.FixtureSpec);
const CompiledFixture = ability.compile(
    "fixture.label.mismatch",
    LoweredFixture.runtime_plan,
    .{ .stable_build_fingerprint_seed = "ability-comptime-label-mismatch-negative" },
);

test "compile rejects mismatched plan labels" {
    _ = CompiledFixture;
}
