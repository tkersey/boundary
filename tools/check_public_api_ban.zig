const std = @import("std");

const allowed_exports = &[_][]const u8{
    "Runtime",
    "RuntimeError",
    "ErrorWitnessV1",
    "Decision",
    "Decl",
    "Op",
    "Ops",
    "Program",
    "run",
};

const BanError = error{PublicApiBanViolation};

fn trimWhitespace(line: []const u8) []const u8 {
    var start: usize = 0;
    while (start < line.len and std.ascii.isWhitespace(line[start])) : (start += 1) {}
    var end: usize = line.len;
    while (end > start and std.ascii.isWhitespace(line[end - 1])) : (end -= 1) {}
    return line[start..end];
}

fn readIdentifier(line: []const u8, start: usize) []const u8 {
    var idx = start;
    while (idx < line.len) {
        const c = line[idx];
        if ((c >= 'A' and c <= 'Z') or (c >= 'a' and c <= 'z') or (c >= '0' and c <= '9') or c == '_') {
            idx += 1;
            continue;
        }
        break;
    }
    return line[start..idx];
}

fn contains(slice: []const []const u8, value: []const u8) bool {
    for (slice) |entry| if (std.mem.eql(u8, entry, value)) return true;
    return false;
}

/// Run this public entrypoint.
pub fn main() anyerror!void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const path = "src/root.zig";
    const content = try std.fs.cwd().readFileAlloc(allocator, path, std.math.maxInt(usize));
    defer allocator.free(content);

    var names = std.ArrayList([]const u8).empty;
    defer names.deinit(allocator);

    var offset: usize = 0;
    while (offset <= content.len) {
        var line_end = offset;
        while (line_end < content.len and content[line_end] != '\n') : (line_end += 1) {}
        const line = content[offset..line_end];
        const trimmed = trimWhitespace(line);
        if (trimmed.len != 0) {
            const pub_const = "pub const ";
            const pub_fn = "pub fn ";
            if (trimmed.len > pub_const.len and std.mem.startsWith(u8, trimmed, pub_const)) {
                const name = readIdentifier(trimmed, pub_const.len);
                if (name.len != 0 and !contains(names.items, name)) try names.append(allocator, name);
            } else if (trimmed.len > pub_fn.len and std.mem.startsWith(u8, trimmed, pub_fn)) {
                const name = readIdentifier(trimmed, pub_fn.len);
                if (name.len != 0 and !contains(names.items, name)) try names.append(allocator, name);
            }
        }
        if (line_end >= content.len) break;
        offset = line_end + 1;
    }

    var banned = std.ArrayList([]const u8).empty;
    defer banned.deinit(allocator);
    for (names.items) |name| if (!contains(allowed_exports, name)) try banned.append(allocator, name);

    if (banned.items.len != 0) {
        std.debug.print("public API ban failure: disallowed exports found:\\n", .{});
        for (banned.items) |name| std.debug.print("  {s}\\n", .{name});
        return BanError.PublicApiBanViolation;
    }
}
