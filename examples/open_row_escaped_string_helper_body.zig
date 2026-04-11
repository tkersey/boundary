const shift_compile = @import("shift_compile");
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
pub fn loweringSpec() shift_compile.lowering.LowerSpec {
    return .{
        .label = "example.open_row_escaped_string_helper_body",
        .entry_symbol = "runBody",
        .row = shift_compile.ir.rowFromSpec(.{
            .writer = .{
                .tell = shift_compile.ir.Transform([]const u8, void),
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
pub fn loweringSource() shift_compile.lowering.SourceRef {
    return shift_compile.lowering.sourceWithContent(loweringSourcePath(), explicitLoweringCaller(), @embedFile(@src().file));
}

/// Return the additive public lowered artifact for this escaped helper-body workflow.
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
