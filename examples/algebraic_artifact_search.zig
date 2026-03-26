const shift = @import("shift");
const std = @import("std");

const transcript = struct {
    threadlocal var items = [_][]const u8{ "", "", "", "", "", "" };
    threadlocal var len: usize = 0;

    fn note(message: []const u8) void {
        items[len] = message;
        len += 1;
    }
};

const search_state = struct {};

const SearchHandler = struct {
    state: search_state = .{},

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

const Search = shift.Decl.family(.{
    .state_type = search_state,
    .ops = .{
        shift.Op.Transform("search", []const u8, i32),
    },
}, SearchHandler);

const ArtifactSearch = shift.Program(.{
    .search = Search,
}, struct {
    /// Trigger the front-door search operation and emit the canonical artifact transcript fields.
    pub fn body(eff: anytype) !i32 {
        const total = try eff.search.search.perform("artifact-search");
        if (total != 3) unreachable;
        transcript.note("messages=1");
        transcript.note("tool_calls=0");
        transcript.note("memory_blocks=1");
        transcript.note("opencode_source=jsonl");
        return total;
    }
});

/// Write the artifact-search transcript through the root front door.
pub fn run(writer: anytype) anyerror!void {
    var runtime = shift.Runtime.init(std.heap.page_allocator);
    defer runtime.deinit();

    transcript.len = 0;
    const result = try shift.run(&runtime, ArtifactSearch, .{
        .search = SearchHandler{},
    });
    for (transcript.items[0..transcript.len]) |item| {
        try writer.print("{s}\n", .{item});
    }
    try writer.print("total={d}\n", .{result.value});
}

/// Run the algebraic artifact-search example.
pub fn main() anyerror!void {
    var stdout_buffer: [512]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    const stdout = &stdout_writer.interface;
    try run(stdout);
    try stdout.flush();
}
