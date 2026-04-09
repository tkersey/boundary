const shift_compile = @import("shift_compile");
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
pub fn loweringSpec() shift_compile.lowering.LowerSpec {
    return .{
        .label = "example.open_row_helper_bool_flow",
        .entry_symbol = "runBody",
        .row = shift_compile.ir.rowFromSpec(.{
            .approval = .{
                .ask = shift_compile.ir.Transform(void, bool),
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
pub fn loweringSource() shift_compile.lowering.SourceRef {
    return shift_compile.lowering.sourceWithContent(loweringSourcePath(), explicitLoweringCaller(), @embedFile(@src().file));
}

/// Return the additive public lowered artifact for this bool helper workflow.
pub fn loweredProgram() @TypeOf(shift_compile.lowering.lowerOpenRowAt(loweringSourcePath(), loweringSpec())) {
    return try shift_compile.lowering.lowerOpenRowAt(loweringSourcePath(), loweringSpec());
}

/// Return the explicit IR view paired with this same-module lowering request.
pub fn irProgram() shift_compile.ir.Program {
    return shift_compile.lowering.irProgramAt(loweringSourcePath(), loweringSpec());
}

fn CompiledProgramType() type {
    return shift_compile.lower(loweringSource(), loweringSpec());
}

/// Generated additive program type exposing the runtime-owned plan bridge.
pub const CompiledProgram = CompiledProgramType();
