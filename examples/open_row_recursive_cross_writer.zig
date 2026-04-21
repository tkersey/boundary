const helpers = @import("open_row_recursive_cross_helpers.zig");
const shift = @import("shift");
const shift_compile = @import("shift_compile");
const std = @import("std");
const runtime_support = shift_compile.lowering.runtime_support;

/// Run one recursive imported-helper workflow through the open-row kernel.
pub fn runBody(eff: anytype) ![]const u8 {
    try helpers.countdown(eff);
    return "done";
}

/// Return the additive public lowering spec for this imported recursive workflow.
pub fn loweringSpec() shift_compile.lowering.LowerSpec {
    return .{
        .label = "example.open_row_recursive_cross_writer",
        .entry_symbol = "runBody",
        .row = shift_compile.ir.mergeRows(.{
            shift_compile.ir.rowFromSpec(.{
                .state = .{
                    .get = shift_compile.ir.Transform(void, i32),
                    .set = shift_compile.ir.Transform(i32, void),
                },
            }),
            shift_compile.ir.rowFromSpec(.{
                .writer = .{
                    .tell = shift_compile.ir.Transform([]const u8, void),
                },
            }),
        }),
        .ValueType = []const u8,
        .outputs = &.{
            .{ .label = "state", .OutputType = i32 },
            .{ .label = "writer", .OutputType = [][]const u8 },
        },
    };
}

/// Return the source path captured by this imported recursive example module.
pub fn loweringSourcePath() [:0]const u8 {
    return "examples/open_row_recursive_cross_writer.zig";
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

/// Return the explicit caller-owned lowering provenance witness for this imported recursive module.
pub fn loweringSource() shift_compile.lowering.SourceRef {
    return shift_compile.lowering.sourceWithContentAndImports(
        loweringSourcePath(),
        explicitLoweringCaller(),
        @embedFile(@src().file),
        &.{shift_compile.lowering.importedSource(
            loweringSourcePath(),
            "open_row_recursive_cross_helpers.zig",
            @embedFile("open_row_recursive_cross_helpers.zig"),
        )},
    );
}

/// Return the lowered artifact for this imported recursive workflow.
pub fn loweredProgram() @TypeOf(shift_compile.lowering.lowerOpenRowAt(loweringSourcePath(), loweringSpec())) {
    return try shift_compile.lowering.lowerOpenRowAt(loweringSourcePath(), loweringSpec());
}

/// Return the explicit IR view paired with this imported recursive lowering request.
pub fn irProgram() shift_compile.ir.Program {
    return shift_compile.lowering.irProgramAt(loweringSourcePath(), loweringSpec());
}

fn CompiledProgramType() type {
    return shift_compile.lower(loweringSource(), loweringSpec());
}

/// Generated additive program type exposing the runtime-owned plan bridge.
pub const CompiledProgram = CompiledProgramType();

fn runWithAllocator(writer: anytype, allocator: std.mem.Allocator) anyerror!void {
    var runtime = shift.Runtime.init(allocator);
    defer runtime.deinit();

    var handlers: runtime_support.StateWriterHandlers = .{
        .state = .{ .value = 2 },
        .writer = .{ .allocator = allocator },
    };
    defer handlers.writer.deinit();

    const result = try CompiledProgram.run(&runtime, &handlers);
    defer runtime_support.deinitWriterOutputs(allocator, result.outputs.writer);

    for (result.outputs.writer) |item| {
        try writer.print("item={s}\n", .{item});
    }
    try writer.print("final_state={d}\n", .{result.outputs.state});
    try writer.print("value={s}\n", .{result.value});
}

/// Write the imported recursive state-plus-writer transcript.
pub fn run(writer: anytype) anyerror!void {
    try runWithAllocator(writer, std.heap.page_allocator);
}
