const shift = @import("shift");
const std = @import("std");

/// Return the additive public lowering spec for this workflow.
pub fn loweringSpec() shift.lowering.LowerSpec {
    return .{
        .label = "example.open_row_state_writer",
        .module_path = "examples/open_row_state_writer.zig",
        .symbol_name = "body",
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
pub fn loweredProgram() anyerror!shift.lowering.LoweredProgram {
    return try shift.lowering.lowerOpenRow(loweringSpec());
}

const WorkflowProgram = shift.Program(.{
    .state = shift.Decl.state(i32),
    .writer = shift.Decl.writer([]const u8),
}, struct {
    /// Run one state-plus-writer workflow through the program kernel.
    pub fn body(eff: anytype) ![]const u8 {
        const before = try eff.state.get();
        try eff.state.set(before + 1);
        try eff.writer.tell("query=artifact-search");
        try eff.writer.tell("workflow=queued");
        return "done";
    }
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
