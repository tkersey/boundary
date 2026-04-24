const shift = @import("shift");
const shift_compile = @import("shift_compile");
const std = @import("std");
const runtime_support = shift_compile.lowering_api.runtime_support;

fn choose(eff: anytype) !void {
    const state = eff.state;
    const writer = eff.writer;
    const before = try state.get();
    if (before == 0) try writer.tell("zero") else try writer.tell("nonzero");
}

/// Run one branching helper-body workflow through the open-row kernel.
pub fn runBody(eff: anytype) ![]const u8 {
    try choose(eff);
    return "done";
}

/// Return the additive public lowering spec for this branching helper-body workflow.
pub fn loweringSpec() shift_compile.lowering_api.LowerSpec {
    return .{
        .label = "example.open_row_branching_helper_body",
        .entry_symbol = "runBody",
        .row = shift_compile.effect_ir.mergeRows(.{
            shift_compile.effect_ir.rowFromSpec(.{
                .state = .{
                    .get = shift_compile.effect_ir.Transform(void, i32),
                },
            }),
            shift_compile.effect_ir.rowFromSpec(.{
                .writer = .{
                    .tell = shift_compile.effect_ir.Transform([]const u8, void),
                },
            }),
        }),
        .ValueType = []const u8,
        .outputs = &.{
            .{ .label = "writer", .OutputType = [][]const u8 },
        },
    };
}

/// Return the source path captured by this branching helper-body example module.
pub fn loweringSourcePath() [:0]const u8 {
    return "examples/open_row_branching_helper_body.zig";
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

/// Return the additive public lowered artifact for this branching helper-body workflow.
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

fn runWithAllocator(writer: anytype, allocator: std.mem.Allocator, initial_state: i32) anyerror!void {
    var runtime = shift.Runtime.init(allocator);
    defer runtime.deinit();

    var handlers: runtime_support.StateWriterHandlers = .{
        .state = .{ .value = initial_state },
        .writer = .{ .allocator = allocator },
    };
    defer handlers.writer.deinit();

    const result = try CompiledProgram.run(&runtime, &handlers);
    defer runtime_support.deinitWriterOutputs(allocator, result.outputs.writer);

    for (result.outputs.writer) |item| {
        try writer.print("item={s}\n", .{item});
    }
    try writer.print("value={s}\n", .{result.value});
}

/// Write the branching helper-body transcript.
pub fn run(writer: anytype) anyerror!void {
    try runWithAllocator(writer, std.heap.page_allocator, 0);
}
