const shift = @import("shift");
const std = @import("std");

const search_row = shift.Row(.{
    .search = .{
        .search = shift.Transform([]const u8, i32),
    },
});

const transcript = struct {
    threadlocal var items = [_][]const u8{ "", "", "", "", "", "" };
    threadlocal var len: usize = 0;

    fn note(message: []const u8) void {
        items[len] = message;
        len += 1;
    }
};

const search_handler = struct {
    /// Record the search query and return the canonical total.
    pub fn search(_: *@This(), payload: []const u8) i32 {
        if (!std.mem.eql(u8, payload, "artifact-search")) unreachable;
        transcript.note("query=artifact-search");
        return 3;
    }

    /// Preserve the resumed search answer unchanged.
    pub fn afterSearch(_: *@This(), answer: i32) i32 {
        return answer;
    }
};

const artifact_search_workflow = struct {
    /// Capability bundle for the artifact search example.
    pub const Uses = shift.Uses(search_row);

    /// Trigger the search operation and emit the canonical transcript fields.
    pub fn body(eff: anytype) anyerror!i32 {
        const total = try eff.search.search.perform("artifact-search");
        if (total != 3) unreachable;
        transcript.note("messages=1");
        transcript.note("tool_calls=0");
        transcript.note("memory_blocks=1");
        transcript.note("opencode_source=jsonl");
        return total;
    }
};

/// Render the artifact-search transcript.
pub fn run(writer: anytype) anyerror!void {
    var runtime = shift.Runtime.init(std.heap.page_allocator);
    defer runtime.deinit();

    transcript.len = 0;
    const closed = shift.bind(artifact_search_workflow, .{
        .search = search_handler{},
    });
    const result = try shift.run(&runtime, closed);
    for (transcript.items[0..transcript.len]) |item| {
        try writer.print("{s}\n", .{item});
    }
    try writer.print("total={d}\n", .{result.value});
}

/// Run the artifact-search example on stdout.
pub fn main() anyerror!void {
    var stdout_buffer: [512]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    const stdout = &stdout_writer.interface;
    try run(stdout);
    try stdout.flush();
}
