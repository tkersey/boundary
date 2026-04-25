const ability_compile = @import("ability_compile");

/// Source module used to generate the public ability_agent_vm smoke fixture.
pub const source_path = "test/fixtures/ability_agent_vm_smoke_source.zig";
/// Committed artifact path for the public ability_agent_vm smoke fixture.
pub const artifact_path = "test/fixtures/ability_agent_vm_smoke.artifact";

/// Shared lowering spec for fixture generation and verification.
pub const FixtureSpec: ability_compile.lowering_api.LowerSpec = .{
    .label = "test.ability_agent_vm_public_smoke",
    .entry_symbol = "runBody",
    .row = ability_compile.effect_ir.rowFromSpec(.{
        .writer = .{
            .tell = ability_compile.effect_ir.Transform([]const u8, void),
        },
    }),
    .ValueType = []const u8,
    .outputs = &.{},
};
