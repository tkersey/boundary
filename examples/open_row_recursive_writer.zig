const ability = @import("ability");
const ability_compile = @import("ability_compile");
const std = @import("std");
const runtime_support = ability_compile.lowering_api.runtime_support;

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
pub fn loweringSpec() ability_compile.lowering_api.LowerSpec {
    return .{
        .label = "example.open_row_recursive_writer",
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

/// Return the source path captured by this recursive example module.
pub fn loweringSourcePath() [:0]const u8 {
    return "examples/open_row_recursive_writer.zig";
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

/// Return the explicit caller-owned lowering provenance witness for this recursive module.
pub fn loweringSource() ability_compile.lowering_api.SourceRef {
    return ability_compile.lowering_api.sourceWithContent(loweringSourcePath(), explicitLoweringCaller(), @embedFile(@src().file));
}

/// Return the lowered artifact for this recursive workflow.
pub fn loweredProgram() @TypeOf(ability_compile.lowering_api.lowerOpenRowAt(loweringSourcePath(), loweringSpec())) {
    return try ability_compile.lowering_api.lowerOpenRowAt(loweringSourcePath(), loweringSpec());
}

/// Return the explicit IR view paired with this recursive lowering request.
pub fn irProgram() ability_compile.effect_ir.Program {
    return ability_compile.lowering_api.irProgramAt(loweringSourcePath(), loweringSpec());
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
        .state = .{ .value = 3 },
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

/// Write the recursive state-plus-writer transcript.
pub fn run(writer: anytype) anyerror!void {
    try runWithAllocator(writer, std.heap.page_allocator);
}
