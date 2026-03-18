const std = @import("std");

const BanError = error{ RetiredSurfaceViolation };

const scan_files = &[_][]const u8{
    "README.md",
    "docs/direct_style_boundary.md",
    "docs/ordinary_zig_contract.md",
    "build.zig",
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

    var violations = std.ArrayList([]const u8).empty;
    defer violations.deinit(allocator);

    inline for (scan_files) |path| {
        const content = try std.fs.cwd().readFileAlloc(allocator, path, std.math.maxInt(usize));
        inline for (banned_patterns) |pattern| {
            if (std.mem.indexOf(u8, content, pattern) != null) {
                try violations.append(allocator, try std.fmt.allocPrint(allocator, "{s}: {s}", .{ path, pattern }));
            }
        }
    }

    if (violations.items.len != 0) {
        std.debug.print("retired root surface ban failure:\n", .{});
        for (violations.items) |line| std.debug.print("  {s}\n", .{line});
        return BanError.RetiredSurfaceViolation;
    }
}
