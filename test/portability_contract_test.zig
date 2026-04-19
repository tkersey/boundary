const std = @import("std");

fn compatIo() std.Io {
    return std.Io.Threaded.global_single_threaded.io();
}

fn expectNoBannedFragments(
    allocator: std.mem.Allocator,
    source_paths: []const []const u8,
    banned_fragments: []const []const u8,
) !void {
    for (source_paths) |source_path| {
        const contents = try std.Io.Dir.cwd().readFileAlloc(compatIo(), source_path, allocator, .limited(std.math.maxInt(usize)));
        defer allocator.free(contents);

        for (banned_fragments) |fragment| {
            try std.testing.expect(std.mem.find(u8, contents, fragment) == null);
        }
    }
}

test "interpreter and kernel stay free of thread-affine primitives" {
    try expectNoBannedFragments(
        std.testing.allocator,
        &.{
            "src/interpreter.zig",
            "src/internal/kernel.zig",
        },
        &.{
            "threadlocal",
            "std.Thread",
            "getCurrentId",
            "Mutex",
        },
    );
}

test "portable core surfaces stay free of thread-affine primitives" {
    try expectNoBannedFragments(
        std.testing.allocator,
        &.{
            "src/portable_core.zig",
            "src/prompt_contract.zig",
            "src/frontend.zig",
            "src/effect/cleanup.zig",
        },
        &.{
            "threadlocal",
            "std.Thread.Mutex",
            "getCurrentId",
        },
    );
}
