const shift = @import("shift");
const std = @import("std");

const transcript = struct {
    threadlocal var abort_line: []const u8 = "";
};

const guard_handler = struct {
    /// Return the canonical abort answer.
    pub fn fail(_: *@This(), payload: []const u8) ![]const u8 {
        transcript.abort_line = payload;
        return "error=missing-name";
    }
};

const Guard = shift.effect.Define(.{
    .state_type = void,
    .ops = .{
        shift.effect.ops.Abort("fail", []const u8),
    },
});

fn abortBody(eff: anytype) anyerror![]const u8 {
    try eff.guard.fail.abort("missing-name");
}

/// Render the abort example transcript.
pub fn run(writer: anytype) anyerror!void {
    var runtime = shift.Runtime.init(std.heap.page_allocator);
    defer runtime.deinit();

    transcript.abort_line = "";
    try writer.writeAll("validate=name\n");
    const result = try shift.withAt(@src(), &runtime, .{
        .guard = Guard.use(.{ .handler = guard_handler{} }),
    }, shift.NamedBody("examples/open_row_abort_basic.zig", "abortBody", anyerror![]const u8, abortBody));
    try writer.print("abort={s}\n", .{transcript.abort_line});
    try writer.print("final={s}\n", .{result.value});
}

/// Run the abort example on stdout.
pub fn main(init: std.process.Init) anyerror!void {
    var stdout_buffer: [256]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(init.io, &stdout_buffer);
    const stdout = &stdout_writer.interface;
    try run(stdout);
    try stdout.flush();
}
