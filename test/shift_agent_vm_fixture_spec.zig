const shift_compile = @import("shift_compile");

/// Source module used to generate the public shift_agent_vm smoke fixture.
pub const source_path = "test/fixtures/shift_agent_vm_smoke_source.zig";
/// Committed artifact path for the public shift_agent_vm smoke fixture.
pub const artifact_path = "test/fixtures/shift_agent_vm_smoke.artifact";

/// Shared lowering spec for fixture generation and verification.
pub const FixtureSpec: shift_compile.lowering_api.LowerSpec = .{
    .label = "test.shift_agent_vm_public_smoke",
    .entry_symbol = "runBody",
    .row = shift_compile.effect_ir.rowFromSpec(.{
        .writer = .{
            .tell = shift_compile.effect_ir.Transform([]const u8, void),
        },
    }),
    .ValueType = []const u8,
    .outputs = &.{},
};
