const shift = @import("shift");

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
pub fn loweringSpec() shift.lowering.LowerSpec {
    return .{
        .label = "example.open_row_linear_helper_body",
        .entry_symbol = "runBody",
        .row = shift.ir.rowFromSpec(.{
            .writer = .{
                .tell = shift.ir.Transform([]const u8, void),
            },
        }),
        .ValueType = []const u8,
        .outputs = &.{
            .{ .label = "writer", .OutputType = [][]const u8 },
        },
    };
}

/// Return the source path captured by this straight-line helper-body example module.
pub fn loweringSourcePath() []const u8 {
    return "examples/open_row_linear_helper_body.zig";
}

/// Return the explicit caller-owned lowering provenance witness for this module.
pub fn loweringSource() shift.lowering.SourceRef {
    return shift.lowering.source(loweringSourcePath(), @src());
}

/// Return the additive public lowered artifact for this straight-line helper-body workflow.
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
