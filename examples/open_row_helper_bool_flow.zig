const shift = @import("shift");

fn preserve(flag: bool, _: anytype) !bool {
    return flag;
}

/// Run one bool-valued helper flow through the open-row kernel.
pub fn runBody(eff: anytype) anyerror!bool {
    const allowed = try eff.approval.ask();
    const preserved = try preserve(allowed, eff);
    return preserved;
}

/// Return the additive public lowering spec for this bool helper workflow.
pub fn loweringSpec() shift.lowering.LowerSpec {
    return .{
        .label = "example.open_row_helper_bool_flow",
        .entry_symbol = "runBody",
        .row = shift.ir.rowFromSpec(.{
            .approval = .{
                .ask = shift.ir.Transform(void, bool),
            },
        }),
        .ValueType = bool,
    };
}

/// Return the source path captured by this bool helper example module.
pub fn loweringSourcePath() []const u8 {
    return "examples/open_row_helper_bool_flow.zig";
}

/// Return the explicit caller-owned lowering provenance witness for this module.
pub fn loweringSource() shift.lowering.SourceRef {
    return shift.lowering.sourceWithContent(loweringSourcePath(), @src(), @embedFile(@src().file));
}

/// Return the additive public lowered artifact for this bool helper workflow.
pub fn loweredProgram() @TypeOf(shift.lowering.lowerOpenRowAt(loweringSourcePath(), loweringSpec())) {
    return try shift.lowering.lowerOpenRowAt(loweringSourcePath(), loweringSpec());
}

/// Return the explicit IR view paired with this same-module lowering request.
pub fn irProgram() shift.ir.Program {
    return shift.lowering.irProgramAt(loweringSourcePath(), loweringSpec());
}

fn CompiledProgramType() type {
    return shift.lower(loweringSource(), loweringSpec());
}

/// Generated additive program type exposing the runtime-owned plan bridge.
pub const CompiledProgram = CompiledProgramType();
