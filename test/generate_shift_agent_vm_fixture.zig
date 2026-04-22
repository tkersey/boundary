const fixture = @import("shift_agent_vm_fixture_spec.zig");
const shift_compile = @import("shift_compile");
const std = @import("std");

/// Regenerate the committed public agent-vm artifact fixture.
pub fn main() anyerror!void {
    var arena_buffer: [1 << 20]u8 = undefined;
    var fixed_buffer_allocator = std.heap.FixedBufferAllocator.init(&arena_buffer);
    const allocator = fixed_buffer_allocator.allocator();
    const bytes = try shift_compile.compileAndEncode(
        allocator,
        fixture.source_path,
        fixture.FixtureSpec,
        .{},
    );
    try std.Io.Dir.cwd().writeFile(std.Io.Threaded.global_single_threaded.io(), .{
        .sub_path = fixture.artifact_path,
        .data = bytes,
        .flags = .{ .truncate = true },
    });
}
