const ability = @import("ability");
const ability_compile = @import("ability_compile");
const std = @import("std");
const runtime_support = ability_compile.lowering_api.runtime_support;

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
pub fn loweringSpec() ability_compile.lowering_api.LowerSpec {
    return .{
        .label = "example.open_row_state_writer",
        .entry_symbol = "runBody",
        .row = ability_compile.effect_ir.mergeRows(.{
            ability_compile.effect_ir.rowFromSpec(.{
                .state = .{
                    .get = ability_compile.effect_ir.Transform(void, i32),
                    .set = ability_compile.effect_ir.Transform(i32, void),
                },
            }),
            ability_compile.effect_ir.rowFromSpec(.{
                .writer = .{
                    .tell = ability_compile.effect_ir.Transform([]const u8, void),
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
pub fn loweredProgram() @TypeOf(ability_compile.lowering_api.lowerOpenRowAt(loweringSourcePath(), loweringSpec())) {
    return try ability_compile.lowering_api.lowerOpenRowAt(loweringSourcePath(), loweringSpec());
}

/// Return the explicit IR view paired with this same-module lowering request.
pub fn irProgram() ability_compile.effect_ir.Program {
    return ability_compile.lowering_api.irProgramAt(loweringSourcePath(), loweringSpec());
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
pub fn loweringSource() ability_compile.lowering_api.SourceRef {
    return ability_compile.lowering_api.sourceWithContent(loweringSourcePath(), explicitLoweringCaller(), @embedFile(@src().file));
}

/// Return the raw caller file string reported by `@src()` inside this module.
pub fn callerSourceFile() []const u8 {
    return @src().file;
}

fn CompiledProgramType() type {
    return ability_compile.lower(loweringSource(), loweringSpec());
}

/// Generated additive program type exposing the runtime-owned plan bridge.
pub const CompiledProgram = CompiledProgramType();

fn runWithAllocator(writer: anytype, allocator: std.mem.Allocator) anyerror!void {
    var runtime = ability.Runtime.init(allocator);
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
