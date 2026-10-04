//! Test-only failure sweeps require a repeatable sequence of allocation sites.
//! SafeAllocator can resize/remap according to address-space availability, so
//! the same operation otherwise has different allocation counts between runs.
//! Force its allocation/copy fallback for the sweep; normal-path tests retain
//! the actual diagnostic allocator, including successful resizing and remapping.
const std = @import("std");

pub fn check(backing: std.mem.Allocator, comptime operation: anytype, args: anytype) !void {
    var fixed_growth = std.testing.FailingAllocator.init(backing, .{ .resize_fail_index = 0 });
    try std.testing.checkAllAllocationFailures(fixed_growth.allocator(), operation, args);
}
