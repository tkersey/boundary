const std = @import("std");

const InventoryError = error{RetiredLaneInventoryViolation};

const file_targets = &[_][]const u8{
    "README.md",
    "build.zig",
    "docs/direct_style_boundary.md",
    "docs/source_lowering_contract.md",
    "docs/source_lowering_matrix.json",
    "docs/source_lowering_coverage_matrix.json",
    "docs/surface_truth_scorecard.json",
    "docs/shipped_surface_frontier_matrix.json",
    "src/source_lowering_registry.zig",
    "src/source_lowering.zig",
    "src/source_lowering_coverage_registry.zig",
    "src/shipped_surface_frontier_registry.zig",
    "test/size_check.zig",
    "test/source_lowering_boundary_test.zig",
    "test/source_lowering_corpus_test.zig",
    "test/source_lowering_promoted_cohort_test.zig",
    "test/source_lowering_completion_test.zig",
    "test/source_lowering_contract/run.sh",
    "test/source_lowering_tool_contract/run.sh",
    "test/source_lowering_error_witness/run.sh",
    "tools/shift_source_lower.zig",
    "tools/render_source_lowering_matrix.zig",
    "tools/render_source_lowering_coverage_matrix.zig",
    "tools/render_surface_truth_scorecard.zig",
    "tools/check_public_api_ban.zig",
};

const dir_targets = &[_][]const u8{
    "test/compile_fail",
    "test/source_lowering_corpus/fixtures",
};

const banned_patterns = &[_][]const u8{
    "shift.with(",
    "shift.effect.",
    "shift.algebraic.",
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

fn checkFile(allocator: std.mem.Allocator, violations: *std.ArrayList([]const u8), path: []const u8) !void {
    const content = try std.fs.cwd().readFileAlloc(allocator, path, std.math.maxInt(usize));
    defer allocator.free(content);

    inline for (banned_patterns) |pattern| {
        if (std.mem.indexOf(u8, content, pattern) != null) {
            try violations.append(allocator, try std.fmt.allocPrint(allocator, "{s}: {s}", .{ path, pattern }));
        }
    }
}

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var violations = std.ArrayList([]const u8).empty;
    defer violations.deinit(allocator);

    inline for (file_targets) |path| try checkFile(allocator, &violations, path);

    inline for (dir_targets) |dir_path| {
        var dir = try std.fs.cwd().openDir(dir_path, .{ .iterate = true });
        defer dir.close();
        var iterator = dir.iterate();
        while (try iterator.next()) |entry| {
            if (entry.kind != .file) continue;
            const full_path = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ dir_path, entry.name });
            defer allocator.free(full_path);
            try checkFile(allocator, &violations, full_path);
        }
    }

    if (violations.items.len != 0) {
        std.debug.print("retired lane inventory failure:\n", .{});
        for (violations.items) |line| std.debug.print("  {s}\n", .{line});
        return InventoryError.RetiredLaneInventoryViolation;
    }
}
