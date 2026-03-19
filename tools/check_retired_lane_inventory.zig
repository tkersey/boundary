const std = @import("std");

const InventoryError = error{RetiredLaneInventoryViolation};

const root_file_targets = &[_][]const u8{
    "README.md",
    "FORMAL_CORE.md",
    "build.zig",
};

const root_dir_targets = &[_][]const u8{
    "bench",
    "docs",
    "examples",
    "src",
    "test",
    "tools",
};

const skipped_paths = &[_][]const u8{
    "test/readme_contract/run.sh",
    "tools/check_retired_lane_inventory.zig",
};

const banned_patterns = &[_][]const u8{
    "shift.ordinary",
    "shift.source_lowering",
    "Program.Manifest",
    "ordinary-zig",
    "shift-ordinary",
    "ordinary.",
    "ordinary_",
    "source_lowering_lowering",
    "surface_replacement",
    "replacement ledger",
    "replacement-ledger",
    "legacy_compat_only",
    "ordinary_canonical_surface",
    "root-surface-migration",
    "root_surface_migration",
};

fn isSkippedPath(path: []const u8) bool {
    inline for (skipped_paths) |skipped| {
        if (std.mem.eql(u8, path, skipped)) return true;
    }
    return false;
}

fn checkFile(allocator: std.mem.Allocator, violations: *std.ArrayList([]const u8), path: []const u8) !void {
    if (isSkippedPath(path)) return;
    const content = try std.fs.cwd().readFileAlloc(allocator, path, std.math.maxInt(usize));
    defer allocator.free(content);

    inline for (banned_patterns) |pattern| {
        if (std.mem.indexOf(u8, content, pattern) != null) {
            try violations.append(allocator, try std.fmt.allocPrint(allocator, "{s}: {s}", .{ path, pattern }));
        }
    }
}

fn checkDirRecursive(allocator: std.mem.Allocator, violations: *std.ArrayList([]const u8), dir_path: []const u8) !void {
    var dir = try std.fs.cwd().openDir(dir_path, .{ .iterate = true });
    defer dir.close();
    var iterator = dir.iterate();
    while (try iterator.next()) |entry| {
        const full_path = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ dir_path, entry.name });
        defer allocator.free(full_path);

        switch (entry.kind) {
            .file => try checkFile(allocator, violations, full_path),
            .directory => try checkDirRecursive(allocator, violations, full_path),
            else => {},
        }
    }
}

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var violations = std.ArrayList([]const u8).empty;
    defer violations.deinit(allocator);

    inline for (root_file_targets) |path| try checkFile(allocator, &violations, path);
    inline for (root_dir_targets) |dir_path| try checkDirRecursive(allocator, &violations, dir_path);

    if (violations.items.len != 0) {
        std.debug.print("retired lane inventory failure:\n", .{});
        for (violations.items) |line| std.debug.print("  {s}\n", .{line});
        return InventoryError.RetiredLaneInventoryViolation;
    }
}
