const std = @import("std");

const expected_snapshot =
    \\{
    \\  "root_exports": [
    \\    "compat",
    \\    "effect",
    \\    "durable",
    \\    "ir",
    \\    "interpreter",
    \\    "lowering",
    \\    "lowerAt",
    \\    "With",
    \\    "with",
    \\    "Runtime",
    \\    "RuntimeError",
    \\    "ErrorWitnessV1",
    \\    "Decl",
    \\    "Op",
    \\    "Decision",
    \\    "Program",
    \\    "run"
    \\  ]
    \\}
;

const SnapshotError = error{SnapshotMismatch};

fn trimAll(bytes: []const u8) []const u8 {
    var start: usize = 0;
    while (start < bytes.len and std.ascii.isWhitespace(bytes[start])) : (start += 1) {}
    var end: usize = bytes.len;
    while (end > start and std.ascii.isWhitespace(bytes[end - 1])) : (end -= 1) {}
    return bytes[start..end];
}

fn trimWhitespace(line: []const u8) []const u8 {
    var start: usize = 0;
    while (start < line.len and std.ascii.isWhitespace(line[start])) : (start += 1) {}
    var end: usize = line.len;
    while (end > start and std.ascii.isWhitespace(line[end - 1])) : (end -= 1) {}
    return line[start..end];
}

fn readIdentifier(line: []const u8, start: usize) []const u8 {
    var idx = start;
    while (idx < line.len) : (idx += 1) {
        const c = line[idx];
        if ((c >= 'A' and c <= 'Z') or (c >= 'a' and c <= 'z') or (c >= '0' and c <= '9') or c == '_') continue;
        break;
    }
    return line[start..idx];
}

fn braceDelta(line: []const u8) isize {
    var delta: isize = 0;
    for (line) |c| switch (c) {
        '{' => delta += 1,
        '}' => delta -= 1,
        else => {},
    };
    return delta;
}

fn buildSnapshot(allocator: std.mem.Allocator) anyerror![]u8 {
    const content = try std.fs.cwd().readFileAlloc(allocator, "src/root.zig", std.math.maxInt(usize));
    var exports = std.ArrayList([]const u8).empty;
    defer exports.deinit(allocator);

    var offset: usize = 0;
    var depth: isize = 0;
    while (offset <= content.len) {
        var line_end = offset;
        while (line_end < content.len and content[line_end] != '\n') : (line_end += 1) {}
        const trimmed = trimWhitespace(content[offset..line_end]);
        if (depth == 0 and trimmed.len != 0) {
            const pub_const = "pub const ";
            const pub_inline_fn = "pub inline fn ";
            const pub_fn = "pub fn ";
            if (trimmed.len > pub_const.len and std.mem.startsWith(u8, trimmed, pub_const)) {
                try exports.append(allocator, try allocator.dupe(u8, readIdentifier(trimmed, pub_const.len)));
            } else if (trimmed.len > pub_inline_fn.len and std.mem.startsWith(u8, trimmed, pub_inline_fn)) {
                try exports.append(allocator, try allocator.dupe(u8, readIdentifier(trimmed, pub_inline_fn.len)));
            } else if (trimmed.len > pub_fn.len and std.mem.startsWith(u8, trimmed, pub_fn)) {
                try exports.append(allocator, try allocator.dupe(u8, readIdentifier(trimmed, pub_fn.len)));
            }
        }
        depth += braceDelta(content[offset..line_end]);
        if (line_end >= content.len) break;
        offset = line_end + 1;
    }

    var out = std.ArrayList(u8).empty;
    errdefer out.deinit(allocator);
    try out.appendSlice(allocator, "{\n  \"root_exports\": [\n");
    for (exports.items, 0..) |item, index| {
        try out.appendSlice(allocator, "    \"");
        try out.appendSlice(allocator, item);
        try out.appendSlice(allocator, "\"");
        try out.appendSlice(allocator, if (index + 1 == exports.items.len) "\n" else ",\n");
    }
    try out.appendSlice(allocator, "  ]\n}\n");
    return try out.toOwnedSlice(allocator);
}

/// Run this public entrypoint.
pub fn main() anyerror!void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const actual = try buildSnapshot(allocator);
    if (!std.mem.eql(u8, trimAll(actual), trimAll(expected_snapshot))) {
        std.debug.print("public root contract snapshot mismatch\nexpected:\n{s}\nactual:\n{s}\n", .{ expected_snapshot, actual });
        return SnapshotError.SnapshotMismatch;
    }
}
