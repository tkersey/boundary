const effect_ir = @import("effect_ir");
const program_frontend = @import("program_frontend");
const source_lowering = @import("source_lowering");

/// Public additive spec for one open-row lowering request.
pub const LowerSpec = struct {
    label: []const u8,
    module_path: []const u8,
    symbol_name: []const u8,
    row: effect_ir.Row,
    outputs: []const effect_ir.OutputSpec = &.{},
    call_edges: []const effect_ir.CallEdge = &.{},
};

/// Public additive open-row program payload.
pub const OpenRowProgram = program_frontend.OpenRowProgram;
/// Public additive lowered open-row artifact.
pub const LoweredProgram = source_lowering.OpenRowGeneratedProgram;
/// Public additive lowering error surface.
pub const LowerError = effect_ir.NormalizeError;

/// Public additive constructors over the retained open-row frontend.
pub const open_rows = program_frontend.open_rows;

/// Build one public additive open-row lowering payload.
pub fn openRow(comptime spec: LowerSpec) OpenRowProgram {
    return .{
        .label = spec.label,
        .function = .{
            .symbol = .{
                .module_path = spec.module_path,
                .symbol_name = spec.symbol_name,
            },
            .row = spec.row,
            .outputs = spec.outputs,
        },
        .call_edges = spec.call_edges,
    };
}

/// Lower one public additive open-row payload into the retained effect-ir shell.
pub fn lowerOpenRow(comptime spec: LowerSpec) LowerError!LoweredProgram {
    return try source_lowering.lowerOpenRowProgram(openRow(spec));
}

test "public additive lowerOpenRow preserves the state-writer workflow digest" {
    const lowered = try lowerOpenRow(.{
        .label = "example.open_row_state_writer",
        .module_path = "examples/open_row_state_writer.zig",
        .symbol_name = "body",
        .row = effect_ir.mergeRows(.{
            effect_ir.rowFromSpec(.{
                .state = .{
                    .get = effect_ir.Transform(void, i32),
                    .set = effect_ir.Transform(i32, void),
                },
            }),
            effect_ir.rowFromSpec(.{
                .writer = .{
                    .tell = effect_ir.Transform([]const u8, void),
                },
            }),
        }),
        .outputs = &.{
            .{ .label = "state", .OutputType = i32 },
            .{ .label = "writer", .OutputType = [][]const u8 },
        },
    });

    try @import("std").testing.expectEqualStrings("example.open_row_state_writer", lowered.label);
    try @import("std").testing.expectEqual(@as(usize, 2), lowered.normalization.requirement_count);
    try @import("std").testing.expectEqual(@as(usize, 3), lowered.normalization.op_count);
    try @import("std").testing.expectEqual(@as(usize, 2), lowered.normalization.output_count);
}
