const ability = @import("ability");
const ability_compile = @import("ability_compile");
const example = @import("example_custom_approval_workflow");

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

const custom_directory_handler = struct {
    /// Match the generated directory transform handler signature for row extraction.
    pub fn exists(_: *@This(), _: []const u8) bool {
        return true;
    }
};

const custom_approval_handler = struct {
    /// Match the generated approval choice handler signature for row extraction.
    pub fn request(_: *@This(), _: []const u8) ability.effect.choice.Decision([]const u8, []const u8) {
        return ability.effect.choice.Decision([]const u8, []const u8).resumeWith("approved");
    }

    /// Preserve the approval answer after continuation replay for row extraction.
    pub fn afterRequest(_: *@This(), answer: []const u8) []const u8 {
        return answer;
    }
};

const custom_guard_handler = struct {
    /// Match the generated guard abort handler signature for row extraction.
    pub fn invalid(_: *@This(), _: []const u8) []const u8 {
        return "invalid:missing";
    }
};

const CustomDirectoryBinding = @TypeOf(example.directory.use(.{ .handler = custom_directory_handler{} })).BindingSchema("directory");
const CustomApprovalBinding = @TypeOf(example.approval.use(.{ .handler = custom_approval_handler{} })).BindingSchema("approval");
const CustomGuardBinding = @TypeOf(example.guard.use(.{ .handler = custom_guard_handler{} })).BindingSchema("guard");

const custom_approval_generated_row = ability_compile.effect_ir.mergeRows(.{
    ability_compile.effect_schema.row(CustomDirectoryBinding),
    ability_compile.effect_schema.row(CustomApprovalBinding),
    ability_compile.effect_schema.row(CustomGuardBinding),
});

/// Shared lowering spec for the generated-row custom approval workflow ArtifactV1 fixture.
pub const CustomApprovalSpec: ability_compile.lowering_api.LowerSpec = .{
    .label = "example.custom_approval_workflow",
    .entry_symbol = "approvalRuntimeBody",
    .row = custom_approval_generated_row,
    .ValueType = []const u8,
    .outputs = &.{},
};
