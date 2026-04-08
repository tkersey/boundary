const std = @import("std");

const banned_fragments = &[_][]const u8{
    "threadlocal",
    "std.Thread",
    "getCurrentId",
    "Mutex",
};

const CheckError = error{PortableInterpreterViolation};

/// Run this public entrypoint.
pub fn main() anyerror!void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const source_paths = &[_][]const u8{
        "src/interpreter.zig",
        "src/internal/kernel.zig",
    };

    var violations: usize = 0;
    for (source_paths) |source_path| {
        const contents = try std.fs.cwd().readFileAlloc(allocator, source_path, std.math.maxInt(usize));
        defer allocator.free(contents);

        for (banned_fragments) |fragment| {
            if (std.mem.indexOf(u8, contents, fragment) != null) {
                std.debug.print("portable interpreter violation in {s}: found banned fragment `{s}`\n", .{ source_path, fragment });
                violations += 1;
            }
        }
    }

    if (violations != 0) return CheckError.PortableInterpreterViolation;
}
