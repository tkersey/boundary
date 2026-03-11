const shift = @import("shift");
const std = @import("std");

pub fn main() anyerror!void {
    var stdout_buffer: [256]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    const stdout = &stdout_writer.interface;

    var alloc_calls: usize = 0;
    var total: usize = 0;

    const CountingAllocator = struct {
        count: *usize,

        fn allocator(self: *@This()) std.mem.Allocator {
            return .{
                .ptr = self,
                .vtable = &.{
                    .alloc = alloc,
                    .resize = resize,
                    .remap = remap,
                    .free = free,
                },
            };
        }

        fn alloc(ctx: *anyopaque, len: usize, alignment: std.mem.Alignment, ra: usize) ?[*]u8 {
            const self: *@This() = @ptrCast(@alignCast(ctx));
            self.count.* += 1;
            return std.heap.smp_allocator.rawAlloc(len, alignment, ra);
        }

        fn resize(ctx: *anyopaque, memory: []u8, alignment: std.mem.Alignment, new_len: usize, ra: usize) bool {
            _ = ctx;
            return std.heap.smp_allocator.rawResize(memory, alignment, new_len, ra);
        }

        fn remap(ctx: *anyopaque, memory: []u8, alignment: std.mem.Alignment, new_len: usize, ra: usize) ?[*]u8 {
            _ = ctx;
            return std.heap.smp_allocator.rawRemap(memory, alignment, new_len, ra);
        }

        fn free(ctx: *anyopaque, memory: []u8, alignment: std.mem.Alignment, ra: usize) void {
            _ = ctx;
            std.heap.smp_allocator.rawFree(memory, alignment, ra);
        }
    };

    var counting = CountingAllocator{ .count = &alloc_calls };
    _ = counting.allocator();

    for (0..100_000) |i| total += @intCast(shift.generated.no_capture.noCapture(@intCast(i)));

    try stdout.print("alloc_calls={d}\n", .{alloc_calls});
    try stdout.print("total={d}\n", .{total});
    try stdout.flush();
}
