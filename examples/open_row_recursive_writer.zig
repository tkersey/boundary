const shift = @import("shift");
const std = @import("std");

fn countdown(eff: anytype) !void {
    const remaining = try eff.state.get();
    if (remaining == 0) return;
    try eff.writer.tell("tick");
    try eff.state.set(remaining - 1);
    try countdown(eff);
}

/// Run one recursive state-plus-writer workflow through the open-row kernel.
pub fn runBody(eff: anytype) ![]const u8 {
    try countdown(eff);
    return "done";
}

/// Return the additive public lowering spec for this recursive workflow.
pub fn loweringSpec() shift.lowering.LowerSpec {
    return .{
        .label = "example.open_row_recursive_writer",
        .entry_symbol = "runBody",
        .row = shift.ir.mergeRows(.{
            shift.ir.rowFromSpec(.{
                .state = .{
                    .get = shift.ir.Transform(void, i32),
                    .set = shift.ir.Transform(i32, void),
                },
            }),
            shift.ir.rowFromSpec(.{
                .writer = .{
                    .tell = shift.ir.Transform([]const u8, void),
                },
            }),
        }),
        .outputs = &.{
            .{ .label = "state", .OutputType = i32 },
            .{ .label = "writer", .OutputType = [][]const u8 },
        },
    };
}

/// Return the source path captured by this recursive example module.
pub fn loweringSourcePath() []const u8 {
    return "examples/open_row_recursive_writer.zig";
}

/// Return the explicit caller-owned lowering provenance witness for this recursive module.
pub fn loweringSource() shift.lowering.SourceRef {
    return shift.lowering.source(loweringSourcePath(), @src());
}

/// Return the lowered artifact for this recursive workflow.
pub fn loweredProgram() @TypeOf(shift.lowering.lowerOpenRowAt(loweringSourcePath(), loweringSpec())) {
    return try shift.lowering.lowerOpenRowAt(loweringSourcePath(), loweringSpec());
}

/// Return the explicit IR view paired with this recursive lowering request.
pub fn irProgram() shift.ir.Program {
    return shift.lowering.irProgramAt(loweringSourcePath(), loweringSpec());
}

fn CompiledProgramType() type {
    return shift.lower(loweringSource(), loweringSpec());
}

/// Generated additive program type exposing the runtime-owned plan bridge.
pub const CompiledProgram = CompiledProgramType();

const WorkflowProgram = shift.Program(.{
    .state = shift.Decl.state(i32),
    .writer = shift.Decl.writer([]const u8),
}, struct {
    /// Reuse the top-level recursive workflow body through the retained kernel-facing alias.
    pub const body = runBody;
});

fn runWithAllocator(writer: anytype, allocator: std.mem.Allocator) anyerror!void {
    var runtime = shift.Runtime.init(allocator);
    defer runtime.deinit();

    const result = try shift.run(&runtime, WorkflowProgram, .{ .state = 3 });
    defer allocator.free(result.outputs.writer);

    for (result.outputs.writer) |item| {
        try writer.print("item={s}\n", .{item});
    }
    try writer.print("final_state={d}\n", .{result.outputs.state});
    try writer.print("value={s}\n", .{result.value});
}

/// Write the recursive state-plus-writer transcript.
pub fn run(writer: anytype) anyerror!void {
    try runWithAllocator(writer, std.heap.page_allocator);
}
