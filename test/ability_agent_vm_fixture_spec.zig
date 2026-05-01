const ability_compile = @import("ability_compile");

/// Source module used to generate the public ability_agent_vm smoke fixture.
pub const source_path = "test/fixtures/ability_agent_vm_smoke_source.zig";
/// Committed artifact path for the public ability_agent_vm smoke fixture.
pub const artifact_path = "test/fixtures/ability_agent_vm_smoke.artifact";
/// Committed artifact path for the custom approval workflow runtime fixture.
pub const custom_approval_artifact_path = "test/fixtures/custom_approval_workflow.artifact";

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

/// Shared lowering spec for the custom approval workflow ArtifactV1 fixture.
pub const CustomApprovalSpec: ability_compile.lowering_api.LowerSpec = .{
    .label = "example.custom_approval_workflow",
    .entry_symbol = "approvalRuntimeBody",
    .row = ability_compile.effect_ir.mergeRows(.{
        ability_compile.effect_ir.rowFromSpec(.{
            .directory = .{
                .exists = ability_compile.effect_ir.Transform([]const u8, bool),
            },
        }),
        ability_compile.effect_ir.rowFromSpec(.{
            .approval = .{
                .request = ability_compile.effect_ir.Choice([]const u8, []const u8),
            },
        }),
        ability_compile.effect_ir.rowFromSpec(.{
            .guard = .{
                .invalid = ability_compile.effect_ir.Abort([]const u8),
            },
        }),
    }),
    .ValueType = []const u8,
    .outputs = &.{},
};
