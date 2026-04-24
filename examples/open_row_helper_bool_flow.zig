const ability_compile = @import("ability_compile");
const std = @import("std");

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
pub fn loweringSpec() ability_compile.lowering_api.LowerSpec {
    return .{
        .label = "example.open_row_helper_bool_flow",
        .entry_symbol = "runBody",
        .row = ability_compile.effect_ir.rowFromSpec(.{
            .approval = .{
                .ask = ability_compile.effect_ir.Transform(void, bool),
            },
        }),
        .ValueType = bool,
    };
}

/// Return the source path captured by this bool helper example module.
pub fn loweringSourcePath() [:0]const u8 {
    return "examples/open_row_helper_bool_flow.zig";
}

fn explicitLoweringCaller() std.builtin.SourceLocation {
    const src = @src();
    return .{
        .module = src.module,
        .file = loweringSourcePath(),
        .line = src.line,
        .column = src.column,
        .fn_name = src.fn_name,
    };
}

/// Return the explicit caller-owned lowering provenance witness for this module.
pub fn loweringSource() ability_compile.lowering_api.SourceRef {
    return ability_compile.lowering_api.sourceWithContent(loweringSourcePath(), explicitLoweringCaller(), @embedFile(@src().file));
}

/// Return the additive public lowered artifact for this bool helper workflow.
pub fn loweredProgram() @TypeOf(ability_compile.lowering_api.lowerOpenRowAt(loweringSourcePath(), loweringSpec())) {
    return try ability_compile.lowering_api.lowerOpenRowAt(loweringSourcePath(), loweringSpec());
}

/// Return the explicit IR view paired with this same-module lowering request.
pub fn irProgram() ability_compile.effect_ir.Program {
    return ability_compile.lowering_api.irProgramAt(loweringSourcePath(), loweringSpec());
}

fn CompiledProgramType() type {
    return ability_compile.lower(loweringSource(), loweringSpec());
}

/// Generated additive program type exposing the runtime-owned plan bridge.
pub const CompiledProgram = CompiledProgramType();
