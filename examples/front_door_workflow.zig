const shift = @import("shift");
const std = @import("std");

const transcript = struct {
    threadlocal var approval_line: []const u8 = "";
    threadlocal var search_line: []const u8 = "";
};

const search_state = struct {};

const SearchHandler = struct {
    state: search_state = .{},

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
    /// Approve publication through the composite front-door example.
    pub fn publish(_: *@This()) shift.Decision([]const u8, []const u8) {
        transcript.approval_line = "approval=publish";
        return shift.Decision([]const u8, []const u8).returnNow("completed");
    }

    /// Preserve the resumed workflow result unchanged.
    pub fn afterPublish(_: *@This(), answer: []const u8) []const u8 {
        return answer;
    }
};

const Workflow = shift.Program(.{
    .state = shift.Decl.state(i32),
    .writer = shift.Decl.writer([]const u8),
    .search = shift.Decl.family(.{
        .state_type = search_state,
        .ops = .{
            shift.Ops.Transform("search", []const u8, i32),
        },
    }, SearchHandler),
    .approval = shift.Decl.family(.{
        .state_type = struct {},
        .ops = .{
            shift.Ops.Choice("publish", void, []const u8),
        },
    }, approval_handler),
}, struct {
    /// Run one composite workflow through the root front door.
    pub fn body(eff: anytype) ![]const u8 {
        const total = try eff.search.search.perform("artifact-search");
        try eff.writer.tell("query=artifact-search");
        const before = try eff.state.get();
        try eff.state.set(before + total);
        try eff.writer.tell("workflow=queued");
        return try eff.approval.publish.perform(struct {
            /// The approval return-now branch must skip the continuation.
            pub fn apply(_: []const u8, _: anytype) ![]const u8 {
                unreachable;
            }
        });
    }
});

fn runWithAllocator(writer: anytype, allocator: std.mem.Allocator) anyerror!void {
    var runtime = shift.Runtime.init(allocator);
    defer runtime.deinit();

    transcript.search_line = "";
    transcript.approval_line = "";
    const result = try shift.run(&runtime, Workflow, .{
        .state = @as(i32, 0),
        .search = SearchHandler{},
        .approval = approval_handler{},
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

/// Write the composite front-door workflow transcript.
pub fn run(writer: anytype) anyerror!void {
    try runWithAllocator(writer, std.heap.page_allocator);
}

/// Run the composite front-door workflow example.
pub fn main() anyerror!void {
    var stdout_buffer: [512]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    const stdout = &stdout_writer.interface;
    try run(stdout);
    try stdout.flush();
}
