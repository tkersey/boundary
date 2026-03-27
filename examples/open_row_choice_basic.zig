const shift = @import("shift");
const std = @import("std");

const picker_row = shift.Row(.{
    .picker = .{
        .pick = shift.Choice(i32, i32),
    },
});

const transcript = struct {
    threadlocal var items = [_][]const u8{ "", "", "", "", "", "", "", "" };
    threadlocal var len: usize = 0;

    fn note(message: []const u8) void {
        items[len] = message;
        len += 1;
    }
};

const picker_handler = struct {
    branch: enum { resume_with, return_now },

    /// Choose the configured branch.
    pub fn pick(self: *@This(), payload: i32) !shift.Decision(i32, []const u8) {
        return switch (self.branch) {
            .return_now => blk: {
                transcript.note("policy-return-now");
                break :blk shift.Decision(i32, []const u8).returnNow("result=early");
            },
            .resume_with => blk: {
                transcript.note("policy-resume");
                break :blk shift.Decision(i32, []const u8).resumeWith(payload);
            },
        };
    }

    /// Finalize the configured choice answer.
    pub fn afterPick(self: *@This(), answer: []const u8) ![]const u8 {
        if (self.branch == .resume_with) transcript.note("policy-after-resume");
        return answer;
    }
};

const picker_workflow = struct {
    /// Capability bundle for the choice example.
    pub const Uses = shift.Uses(picker_row);

    /// Trigger the choice point and complete the configured branch.
    pub fn body(eff: anytype) ![]const u8 {
        return try eff.picker.pick.perform(41, struct {
            /// Resume the continuation with the canonical final answer.
            pub fn apply(value: i32, _: anytype) ![]const u8 {
                if (value != 41) unreachable;
                transcript.note("body-after-pick");
                return "answer=42";
            }
        });
    }
};

/// Render the choice example transcript.
pub fn run(writer: anytype) anyerror!void {
    var runtime = shift.Runtime.init(std.heap.page_allocator);
    defer runtime.deinit();

    try writer.writeAll("branch=return_now\n");
    transcript.len = 0;
    const return_now_closed = shift.bind(picker_workflow, .{
        .picker = picker_handler{ .branch = .return_now },
    });
    const early = try shift.run(&runtime, return_now_closed);
    for (transcript.items[0..transcript.len]) |item| {
        try writer.print("{s}\n", .{item});
    }
    try writer.print("final={s}\n", .{early.value});

    try writer.writeAll("branch=resume_with\n");
    transcript.len = 0;
    const resume_closed = shift.bind(picker_workflow, .{
        .picker = picker_handler{ .branch = .resume_with },
    });
    const resumed = try shift.run(&runtime, resume_closed);
    for (transcript.items[0..transcript.len]) |item| {
        try writer.print("{s}\n", .{item});
    }
    try writer.print("final={s}\n", .{resumed.value});
}

/// Run the choice example on stdout.
pub fn main() anyerror!void {
    var stdout_buffer: [256]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    const stdout = &stdout_writer.interface;
    try run(stdout);
    try stdout.flush();
}
