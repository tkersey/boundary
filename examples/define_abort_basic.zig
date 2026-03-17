const shift = @import("shift");
const std = @import("std");

const NoError = error{};
const Guard = shift.effect.Define(.{
    .state_type = struct {},
    .error_set_type = NoError,
    .ops = .{
        shift.effect.ops.Abort("fail", []const u8),
    },
});

/// Render the generated lexical abort-family example transcript.
pub fn run(writer: anytype) anyerror!void {
    const transcript = struct {
        threadlocal var abort_line: []const u8 = "";
    };

    const guard_handler = struct {
        /// Validate one missing name and return the canonical generated abort answer.
        pub fn fail(_: *@This(), payload: []const u8) shift.ResetError(NoError)![]const u8 {
            transcript.abort_line = payload;
            return "error=missing-name";
        }
    };

    transcript.abort_line = "";

    try writer.writeAll("validate=name\n");
    const result = try shift.with(.{
        .guard = Guard.use(.{ .handler = guard_handler{} }),
    }, struct {
        /// Trigger the generated lexical abort point directly.
        pub fn body(eff: anytype) shift.ResetError(NoError)![]const u8 {
            try eff.guard.fail.abort("missing-name");
        }
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
