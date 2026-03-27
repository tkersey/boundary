const shift = @import("shift");
const std = @import("std");

const transcript = struct {
    threadlocal var abort_line: []const u8 = "";
};

const GuardHandler = struct {
    state: struct {} = .{},

    /// Validate one missing name and return the canonical front-door abort answer.
    pub fn fail(_: *@This(), payload: []const u8) []const u8 {
        transcript.abort_line = payload;
        return "error=missing-name";
    }
};

const Validation = shift.Program(.{
    .guard = shift.Decl.family(.{
        .state_type = struct {},
        .ops = .{
            shift.Ops.Abort("fail", []const u8),
        },
    }, GuardHandler),
}, struct {
    /// Trigger the front-door abortive operation directly.
    pub fn body(eff: anytype) ![]const u8 {
        try eff.guard.fail.abort("missing-name");
    }
});

/// Write the abortive-validation transcript through the root front door.
pub fn run(writer: anytype) anyerror!void {
    var runtime = shift.Runtime.init(std.heap.page_allocator);
    defer runtime.deinit();

    transcript.abort_line = "";
    try writer.writeAll("validate=name\n");
    const result = try shift.run(&runtime, Validation, .{
        .guard = GuardHandler{},
    });
    try writer.print("abort={s}\n", .{transcript.abort_line});
    try writer.print("final={s}\n", .{result.value});
}

/// Run the algebraic abortive-validation example.
pub fn main() anyerror!void {
    var stdout_buffer: [512]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    const stdout = &stdout_writer.interface;
    try run(stdout);
    try stdout.flush();
}
