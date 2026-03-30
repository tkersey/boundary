const shift = @import("shift");
const std = @import("std");

fn queueQuery(eff: anytype) !void {
    const writer = eff.writer;
    try writer.tell("query=artifact-search");
}

fn advanceState(eff: anytype) !void {
    const state = eff.state;
    const before = try state.get();
    try state.set(before + 1);
    try queueQuery(eff);
}

/// Run one state-plus-writer workflow through the program kernel.
pub fn runBody(eff: anytype) ![]const u8 {
    try advanceState(eff);
    try eff.writer.tell("workflow=queued");
    return "done";
}

/// Return the additive public lowering spec for this workflow.
pub fn loweringSpec() shift.lowering.LowerSpec {
    return .{
        .label = "example.open_row_state_writer",
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

/// Return the additive public lowered artifact for this workflow.
pub fn loweredProgram() @TypeOf(shift.lowering.lowerOpenRowAt(loweringSourcePath(), loweringSpec())) {
    return try shift.lowering.lowerOpenRowAt(loweringSourcePath(), loweringSpec());
}

/// Return the explicit IR view paired with this same-module lowering request.
pub fn irProgram() shift.ir.Program {
    return shift.lowering.irProgramAt(loweringSourcePath(), loweringSpec());
}

/// Return the source path captured by this example module.
pub fn loweringSourcePath() []const u8 {
    return "examples/open_row_state_writer.zig";
}

/// Return the explicit caller-owned lowering provenance witness for this module.
pub fn loweringSource() shift.lowering.SourceRef {
    return shift.lowering.source(loweringSourcePath(), @src());
}

/// Return the raw caller file string reported by `@src()` inside this module.
pub fn callerSourceFile() []const u8 {
    return @src().file;
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
    /// Reuse the top-level workflow body through the retained kernel-facing alias.
    pub const body = runBody;
});

fn runWithAllocator(writer: anytype, allocator: std.mem.Allocator) anyerror!void {
    var runtime = shift.Runtime.init(allocator);
    defer runtime.deinit();

    const result = try shift.run(&runtime, WorkflowProgram, .{ .state = 5 });
    defer allocator.free(result.outputs.writer);

    for (result.outputs.writer) |item| {
        try writer.print("item={s}\n", .{item});
    }
    try writer.print("final_state={d}\n", .{result.outputs.state});
    try writer.print("value={s}\n", .{result.value});
}

/// Write the open-row state-plus-writer transcript.
pub fn run(writer: anytype) anyerror!void {
    try runWithAllocator(writer, std.heap.page_allocator);
}

/// Run the state-plus-writer example on stdout.
pub fn main() anyerror!void {
    var stdout_buffer: [256]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    const stdout = &stdout_writer.interface;
    try run(stdout);
    try stdout.flush();
}
