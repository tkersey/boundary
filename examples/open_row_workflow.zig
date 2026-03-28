const shift = @import("shift");
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
    pub fn publish(_: *@This()) shift.Decision([]const u8, []const u8) {
        transcript.approval_line = "approval=publish";
        return shift.Decision([]const u8, []const u8).returnNow("completed");
    }

    /// Preserve the resumed workflow result unchanged.
    pub fn afterPublish(_: *@This(), answer: []const u8) []const u8 {
        return answer;
    }
};

const SearchDecl = shift.Decl.family(.{
    .state_type = struct {},
    .ops = .{
        shift.Op.Transform("search", []const u8, i32),
    },
}, search_handler);

const ApprovalDecl = shift.Decl.family(.{
    .state_type = void,
    .ops = .{
        shift.Op.Choice("publish", void, []const u8),
    },
}, approval_handler);

const WorkflowProgram = shift.Program(.{
    .state = shift.Decl.state(i32),
    .writer = shift.Decl.writer([]const u8),
    .search = SearchDecl,
    .approval = ApprovalDecl,
}, struct {
    /// Run the composite workflow.
    pub fn body(eff: anytype) ![]const u8 {
        const total = try eff.search.search.perform("artifact-search");
        try eff.writer.tell("query=artifact-search");
        const before = try eff.state.get();
        try eff.state.set(before + total);
        try eff.writer.tell("workflow=queued");
        return try eff.approval.publish.perform(struct {
            /// The return-now branch must skip the continuation.
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
    const result = try shift.run(&runtime, WorkflowProgram, .{
        .state = 0,
        .search = search_handler{},
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

/// Render the workflow example transcript.
pub fn run(writer: anytype) anyerror!void {
    try runWithAllocator(writer, std.heap.page_allocator);
}

/// Run the workflow example on stdout.
pub fn main() anyerror!void {
    var stdout_buffer: [512]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    const stdout = &stdout_writer.interface;
    try run(stdout);
    try stdout.flush();
}
