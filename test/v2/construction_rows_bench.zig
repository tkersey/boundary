const std = @import("std");
const source = @import("boundary").source;
const Id = @import("boundary_data").program.Id;
pub fn main(init: std.process.Init) !void {
    var buffer: [4096]u8 = undefined;
    var out = std.Io.File.stdout().writer(init.io, &buffer);
    for ([_]usize{ 512, 1024, 2048 }) |n| {
        const left = try init.gpa.alloc(Id, n);
        defer init.gpa.free(left);
        const right = try init.gpa.alloc(Id, n);
        defer init.gpa.free(right);
        for (left, right, 0..) |*l, *r, i| {
            l.* = i * 2;
            r.* = i * 2 + 1;
        }
        var samples: [9]u64 = undefined;
        var allocations: usize = 0;
        var allocated: usize = 0;
        for (0..12) |window| {
            var counter = std.testing.FailingAllocator.init(init.gpa, .{});
            const start = std.Io.Clock.awake.now(init.io);
            const result = try (source.Row{ .effects = left }).unionWith(counter.allocator(), .{ .effects = right });
            const elapsed: u64 = @intCast(start.durationTo(std.Io.Clock.awake.now(init.io)).nanoseconds);
            if (result.effects.len != 2 * n) return error.WrongLength;
            for (result.effects, 0..) |id, i| if (id != i) return error.WrongOrder;
            counter.allocator().free(result.effects);
            if (counter.allocated_bytes != counter.freed_bytes) return error.Leak;
            allocations = counter.allocations;
            allocated = counter.allocated_bytes;
            if (window >= 3) samples[window - 3] = elapsed;
        }
        try std.json.Stringify.value(.{ .n = n, .output_ids = 2 * n, .samples_ns = samples, .allocations = allocations, .allocated_bytes = allocated, .original_membership_visits = n * n + n * (n - 1) / 2 }, .{}, &out.interface);
        try out.interface.writeByte('\n');
        try out.interface.flush();
    }
}
