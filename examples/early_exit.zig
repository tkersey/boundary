const shift = @import("shift");
const std = @import("std");

const transcript = struct {
    threadlocal var handler_line: []const u8 = "";
};

const catch_policy = struct {
    /// Recover the direct-return payload into the final front-door answer.
    pub fn directReturn(payload: []const u8) []const u8 {
        transcript.handler_line = "handler-direct-return";
        return payload;
    }
};

fn earlyExitBody(eff: anytype) anyerror![]const u8 {
    try eff.exception.throw("result=early");
}

/// Write the direct-return transcript through the lexical front door.
pub fn run(writer: anytype) anyerror!void {
    var runtime = shift.Runtime.init(std.heap.page_allocator);
    defer runtime.deinit();
    transcript.handler_line = "";

    const result = try shift.withAt(@src(), &runtime, .{
        .exception = shift.effect.exception.use([]const u8, catch_policy),
    }, shift.NamedBody("examples/early_exit.zig", "earlyExitBody", anyerror![]const u8, earlyExitBody));

    try writer.print("{s}\n", .{transcript.handler_line});
    try writer.print("final={s}\n", .{result.value});
}

/// Run the direct-return example.
pub fn main() anyerror!void {
    var stdout_buffer: [256]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    const stdout = &stdout_writer.interface;
    try run(stdout);
    try stdout.flush();
}
