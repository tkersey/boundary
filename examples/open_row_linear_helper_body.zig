const shift_compile = @import("shift_compile");
const std = @import("std");

fn leaf(eff: anytype) !void {
    const writer = eff.writer;
    try writer.tell("leaf");
}

fn helper(eff: anytype) !void {
    const writer = eff.writer;
    try writer.tell("helper");
    try leaf(eff);
}

/// Run one straight-line helper-body workflow through the open-row kernel.
pub fn runBody(eff: anytype) ![]const u8 {
    try helper(eff);
    return "done";
}

/// Return the additive public lowering spec for this straight-line helper-body workflow.
pub fn loweringSpec() shift_compile.lowering_api.LowerSpec {
    return .{
        .label = "example.open_row_linear_helper_body",
        .entry_symbol = "runBody",
        .row = shift_compile.effect_ir.rowFromSpec(.{
            .writer = .{
                .tell = shift_compile.effect_ir.Transform([]const u8, void),
            },
        }),
        .ValueType = []const u8,
        .outputs = &.{
            .{ .label = "writer", .OutputType = [][]const u8 },
        },
    };
}

/// Return the source path captured by this straight-line helper-body example module.
pub fn loweringSourcePath() [:0]const u8 {
    return "examples/open_row_linear_helper_body.zig";
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
pub fn loweringSource() shift_compile.lowering_api.SourceRef {
    return shift_compile.lowering_api.sourceWithContent(loweringSourcePath(), explicitLoweringCaller(), @embedFile(@src().file));
}

/// Return the additive public lowered artifact for this straight-line helper-body workflow.
pub fn loweredProgram() @TypeOf(shift_compile.lowering_api.lowerOpenRowAt(loweringSourcePath(), loweringSpec())) {
    return try shift_compile.lowering_api.lowerOpenRowAt(loweringSourcePath(), loweringSpec());
}

/// Return the explicit IR view paired with this same-module lowering request.
pub fn irProgram() shift_compile.effect_ir.Program {
    return shift_compile.lowering_api.irProgramAt(loweringSourcePath(), loweringSpec());
}

fn CompiledProgramType() type {
    return shift_compile.lower(loweringSource(), loweringSpec());
}

/// Generated additive program type exposing the runtime-owned plan bridge.
pub const CompiledProgram = CompiledProgramType();
