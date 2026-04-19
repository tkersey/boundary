const shift_compile = @import("shift_compile");
const shift_vm = @import("shift_vm");
const std = @import("std");
const shift = shift_vm;
const runtime_support = shift_compile.lowering.runtime_support;

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
pub fn loweringSpec() shift_compile.lowering.LowerSpec {
    return .{
        .label = "example.open_row_state_writer",
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

/// Return the additive public lowered artifact for this workflow.
pub fn loweredProgram() @TypeOf(shift_compile.lowering.lowerOpenRowAt(loweringSourcePath(), loweringSpec())) {
    return try shift_compile.lowering.lowerOpenRowAt(loweringSourcePath(), loweringSpec());
}

/// Return the explicit IR view paired with this same-module lowering request.
pub fn irProgram() shift_compile.ir.Program {
    return shift_compile.lowering.irProgramAt(loweringSourcePath(), loweringSpec());
}

/// Return the source path captured by this example module.
pub fn loweringSourcePath() [:0]const u8 {
    return "examples/open_row_state_writer.zig";
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

/// Return the raw caller file string reported by `@src()` inside this module.
pub fn callerSourceFile() []const u8 {
    return @src().file;
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
        .state = .{ .value = 5 },
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

/// Write the open-row state-plus-writer transcript.
pub fn run(writer: anytype) anyerror!void {
    try runWithAllocator(writer, std.heap.page_allocator);
}

/// Run the state-plus-writer example on stdout.
pub fn main(init: std.process.Init) anyerror!void {
    var stdout_buffer: [256]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(init.io, &stdout_buffer);
    const stdout = &stdout_writer.interface;
    try run(stdout);
    try stdout.flush();
}
