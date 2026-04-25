const ability = @import("ability");
const std = @import("std");

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
        transcript.note("messages=1");
        transcript.note("tool_calls=0");
        transcript.note("memory_blocks=1");
        transcript.note("opencode_source=jsonl");
        return answer;
    }
};

const Search = ability.effect.Define(.{
    .state_type = struct {},
    .ops = .{
        ability.effect.ops.Transform("search", []const u8, i32),
    },
});

fn artifactSearchBody(eff: anytype) anyerror!i32 {
    const total = try eff.search.search.perform("artifact-search");
    return total;
}

/// Render the artifact-search transcript.
pub fn run(writer: anytype) anyerror!void {
    var runtime = ability.Runtime.init(std.heap.page_allocator);
    defer runtime.deinit();

    transcript.len = 0;
    const result = try ability.with(&runtime, .{
        .search = Search.use(.{ .handler = search_handler{} }),
    }, struct {
        /// Run the artifact-search example body through the lexical front door.
        pub fn body(eff: anytype) @TypeOf(artifactSearchBody(eff)) {
            return artifactSearchBody(eff);
        }
    });
    for (transcript.items[0..transcript.len]) |item| {
        try writer.print("{s}\n", .{item});
    }
    try writer.print("total={d}\n", .{result.value});
}

/// Run the artifact-search example on stdout.
pub fn main(init: std.process.Init) anyerror!void {
    var stdout_buffer: [512]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(init.io, &stdout_buffer);
    const stdout = &stdout_writer.interface;
    try run(stdout);
    try stdout.flush();
}
