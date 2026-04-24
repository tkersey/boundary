const ability = @import("ability");
const std = @import("std");

const transcript = struct {
    threadlocal var approval_line: []const u8 = "";
    threadlocal var search_line: []const u8 = "";
};

const search_handler = struct {
    /// Record the search query and return the canonical total.
    pub fn search(_: *@This(), payload: []const u8) i32 {
        if (!std.mem.eql(u8, payload, "artifact-search")) unreachable;
        transcript.search_line = "search=artifact-search";
        return 3;
    }

    /// Preserve the resumed workflow result unchanged after search.
    pub fn afterSearch(_: *@This(), answer: []const u8) []const u8 {
        return answer;
    }
};

const approval_handler = struct {
    /// Approve publication through the workflow example.
    pub fn publish(_: *@This()) ability.effect.choice.Decision([]const u8, []const u8) {
        transcript.approval_line = "approval=publish";
        return ability.effect.choice.Decision([]const u8, []const u8).returnNow("completed");
    }

    /// Preserve the resumed workflow result unchanged.
    pub fn afterPublish(_: *@This(), answer: []const u8) []const u8 {
        return answer;
    }
};

const Search = ability.effect.Define(.{
    .state_type = struct {},
    .ops = .{
        ability.effect.ops.Transform("search", []const u8, i32),
    },
});

const Approval = ability.effect.Define(.{
    .state_type = void,
    .ops = .{
        ability.effect.ops.Choice("publish", void, []const u8),
    },
});

fn workflowBody(eff: anytype) anyerror![]const u8 {
    _ = try eff.search.search.perform("artifact-search");
    try eff.writer.tell("query=artifact-search");
    try eff.state.set(3);
    try eff.writer.tell("workflow=queued");
    return try eff.approval.publish.perform(struct {
        /// The return-now branch must skip the continuation.
        pub fn apply(_: []const u8, _: anytype) ![]const u8 {
            return "unused";
        }
    });
}

fn runWithAllocator(writer: anytype, allocator: std.mem.Allocator) anyerror!void {
    var runtime = ability.Runtime.init(allocator);
    defer runtime.deinit();

    transcript.search_line = "";
    transcript.approval_line = "";
    const result = try ability.with(&runtime, .{
        .state = ability.effect.state.use(@as(i32, 0)),
        .writer = ability.effect.writer.use([]const u8, allocator),
        .search = Search.use(.{ .handler = search_handler{} }),
        .approval = Approval.use(.{ .handler = approval_handler{} }),
    }, struct {
        /// Run the workflow example body through the lexical front door.
        pub fn body(eff: anytype) @TypeOf(workflowBody(eff)) {
            return workflowBody(eff);
        }
    });
    defer allocator.free(result.outputs.writer);

    try writer.print("{s}\n", .{transcript.search_line});
    try writer.print("{s}\n", .{transcript.approval_line});
    for (result.outputs.writer) |item| {
        try writer.print("item={s}\n", .{item});
    }
    try writer.print("final_state={d}\n", .{result.outputs.state});
    try writer.print("total={d}\n", .{result.outputs.state});
    try writer.print("result={s}\n", .{result.value});
}

/// Render the workflow example transcript.
pub fn run(writer: anytype) anyerror!void {
    try runWithAllocator(writer, std.heap.page_allocator);
}

/// Run the workflow example on stdout.
pub fn main(init: std.process.Init) anyerror!void {
    var stdout_buffer: [512]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(init.io, &stdout_buffer);
    const stdout = &stdout_writer.interface;
    try run(stdout);
    try stdout.flush();
}
