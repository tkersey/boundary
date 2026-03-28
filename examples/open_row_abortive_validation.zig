const shift = @import("shift");
const std = @import("std");

const transcript = struct {
    threadlocal var abort_line: []const u8 = "";
};

const guard_handler = struct {
    /// Return the canonical validation failure answer.
    pub fn fail(_: *@This(), payload: []const u8) []const u8 {
        transcript.abort_line = payload;
        return "error=missing-name";
    }
};

const GuardDecl = shift.Decl.family(.{
    .state_type = void,
    .ops = .{
        shift.Op.Abort("fail", []const u8),
    },
}, guard_handler);

const ValidationProgram = shift.Program(.{
    .guard = GuardDecl,
}, struct {
    /// Trigger the validation abort directly.
    pub fn body(eff: anytype) ![]const u8 {
        try eff.guard.fail.abort("missing-name");
    }
});

/// Render the abortive-validation transcript.
pub fn run(writer: anytype) anyerror!void {
    var runtime = shift.Runtime.init(std.heap.page_allocator);
    defer runtime.deinit();

    transcript.abort_line = "";
    try writer.writeAll("validate=name\n");
    const result = try shift.run(&runtime, ValidationProgram, .{ .guard = guard_handler{} });
    try writer.print("abort={s}\n", .{transcript.abort_line});
    try writer.print("final={s}\n", .{result.value});
}

/// Run the abortive-validation example on stdout.
pub fn main() anyerror!void {
    var stdout_buffer: [512]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    const stdout = &stdout_writer.interface;
    try run(stdout);
    try stdout.flush();
}
