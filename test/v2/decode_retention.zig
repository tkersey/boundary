const std = @import("std");
const b = @import("boundary");
pub fn main(init: std.process.Init) !void {
    const a = init.gpa;
    var builder = b.computation.Builder.init(a);
    defer builder.deinit();
    const module = try b.computation.examples.installations(&builder, 64);
    var compiled = try b.program.compile(a, module);
    defer compiled.deinit();
    const bytes = try a.alloc(u8, try b.data.program_image.encodedLength(compiled.program));
    defer a.free(bytes);
    _ = try compiled.encode(a, bytes);
    var tracked = std.testing.FailingAllocator.init(a, .{});
    var decoded = try b.data.program_image.decode(tracked.allocator(), bytes);
    const retained = tracked.allocated_bytes - tracked.freed_bytes;
    const allocations = tracked.allocations;
    decoded.deinit();
    std.debug.assert(tracked.allocated_bytes == tracked.freed_bytes);
    std.debug.print("image_bytes={d} retained_bytes={d} allocations={d}\n", .{ bytes.len, retained, allocations });
}
