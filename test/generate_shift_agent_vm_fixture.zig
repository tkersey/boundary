const shift_compile = @import("shift_compile");
const std = @import("std");

const FixtureSpec: shift_compile.lowering.LowerSpec = .{
    .label = "test.shift_agent_vm_public_smoke",
    .entry_symbol = "runBody",
    .row = shift_compile.ir.rowFromSpec(.{
        .writer = .{
            .tell = shift_compile.ir.Transform([]const u8, void),
        },
    }),
    .ValueType = []const u8,
    .outputs = &.{},
};

/// Regenerate the committed public agent-vm artifact fixture.
pub fn main() anyerror!void {
    var arena_buffer: [1 << 20]u8 = undefined;
    var fixed_buffer_allocator = std.heap.FixedBufferAllocator.init(&arena_buffer);
    const allocator = fixed_buffer_allocator.allocator();
    const bytes = try shift_compile.compileAndEncode(
        allocator,
        "test/fixtures/shift_agent_vm_smoke_source.zig",
        FixtureSpec,
        .{},
    );
    try std.Io.Dir.cwd().writeFile(std.Io.Threaded.global_single_threaded.io(), .{
        .sub_path = "test/fixtures/shift_agent_vm_smoke.artifact",
        .data = bytes,
        .flags = .{ .truncate = true },
    });
}
