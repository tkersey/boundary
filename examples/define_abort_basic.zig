const shift = @import("shift");
const std = @import("std");

const transcript = struct {
    threadlocal var abort_line: []const u8 = "";
};

const guard_handler = struct {
    /// Validate one missing name and return the canonical generated abort answer.
    pub fn fail(_: *@This(), payload: []const u8) ![]const u8 {
        transcript.abort_line = payload;
        return "error=missing-name";
    }
};

const Guard = shift.Decl.family(.{
    .state_type = struct {},
    .ops = .{
        shift.Ops.Abort("fail", []const u8),
    },
}, guard_handler);

const GuardProgram = shift.Program(.{
    .guard = Guard,
}, struct {
    /// Trigger the generated front-door abort point directly.
    pub fn body(eff: anytype) ![]const u8 {
        try eff.guard.fail.abort("missing-name");
    }
});

/// Render the generated lexical abort-family example transcript through the root front door.
pub fn run(writer: anytype) anyerror!void {
    var runtime = shift.Runtime.init(std.heap.page_allocator);
    defer runtime.deinit();

    transcript.abort_line = "";

    try writer.writeAll("validate=name\n");
    const result = try shift.run(&runtime, GuardProgram, .{
        .guard = guard_handler{},
    });
    try writer.print("abort={s}\n", .{transcript.abort_line});
    try writer.print("final={s}\n", .{result.value});
}

/// Run the generated lexical abort-family example on stdout.
pub fn main() anyerror!void {
    var stdout_buffer: [256]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    const stdout = &stdout_writer.interface;
    try run(stdout);
    try stdout.flush();
}
