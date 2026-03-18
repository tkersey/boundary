const std = @import("std");

const InventoryError = error{ LegacyDependenciesRemain };

const scan_targets = &[_]struct {
    category: []const u8,
    path: []const u8,
}{
    .{ .category = "readme", .path = "README.md" },
    .{ .category = "docs", .path = "docs/direct_style_boundary.md" },
    .{ .category = "docs", .path = "docs/ordinary_zig_contract.md" },
    .{ .category = "build", .path = "build.zig" },
};

const banned_patterns = &[_][]const u8{
    "shift.with(",
    "shift.effect.",
    "shift.algebraic.",
    "shift.ordinary",
    "Program.Manifest",
    "ordinary-zig-gauntlet",
    "ordinary-lower",
    "ordinary-error-witness-check",
    "bench-effect-matrix",
    "bench-algebraic-decompose",
    "shared-algebraic-engine-boundary",
};

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var count: usize = 0;
    inline for (scan_targets) |target| {
        const content = try std.fs.cwd().readFileAlloc(allocator, target.path, std.math.maxInt(usize));
        inline for (banned_patterns) |pattern| {
            if (std.mem.indexOf(u8, content, pattern) != null) {
                count += 1;
                std.debug.print("{s}:{s}\n", .{ target.path, pattern });
            }
        }
    }

    if (count != 0) return InventoryError.LegacyDependenciesRemain;
}
