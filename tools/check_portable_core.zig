const std = @import("std");

const banned_fragments = &[_][]const u8{
    "threadlocal",
    "std.Thread.Mutex",
    "getCurrentId",
};

const source_paths = &[_][]const u8{
    "src/portable_core.zig",
    "src/prompt_contract.zig",
    "src/frontend.zig",
    "src/effect/cleanup.zig",
};

const CheckError = error{PortableCoreViolation};

/// Run this public entrypoint.
pub fn main() anyerror!void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var violations: usize = 0;
    for (source_paths) |source_path| {
        const contents = try std.fs.cwd().readFileAlloc(allocator, source_path, std.math.maxInt(usize));
        for (banned_fragments) |fragment| {
            if (std.mem.indexOf(u8, contents, fragment) != null) {
                std.debug.print("portable core violation in {s}: found banned fragment `{s}`\n", .{ source_path, fragment });
                violations += 1;
            }
        }
    }

    if (violations != 0) return CheckError.PortableCoreViolation;
}
