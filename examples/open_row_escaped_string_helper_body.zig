const ability_compile = @import("ability_compile");
const std = @import("std");

fn helper(eff: anytype) !void {
    const writer = eff.writer;
    try writer.tell("line\n");
    try writer.tell("\"");
}

/// Run one helper-body workflow that exercises escaped string literals.
pub fn runBody(eff: anytype) ![]const u8 {
    try helper(eff);
    return "done";
}

/// Return the additive public lowering spec for this escaped helper-body workflow.
pub fn loweringSpec() ability_compile.lowering_api.LowerSpec {
    return .{
        .label = "example.open_row_escaped_string_helper_body",
        .entry_symbol = "runBody",
        .row = ability_compile.effect_ir.rowFromSpec(.{
            .writer = .{
                .tell = ability_compile.effect_ir.Transform([]const u8, void),
            },
        }),
        .ValueType = []const u8,
        .outputs = &.{
            .{ .label = "writer", .OutputType = [][]const u8 },
        },
    };
}

/// Return the source path captured by this escaped helper-body example module.
pub fn loweringSourcePath() [:0]const u8 {
    return "examples/open_row_escaped_string_helper_body.zig";
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

/// Return the additive public lowered artifact for this escaped helper-body workflow.
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
