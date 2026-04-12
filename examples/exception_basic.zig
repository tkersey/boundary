const shift = @import("shift");
const std = @import("std");

const catch_policy = struct {
    /// Recover one thrown payload into the final front-door answer.
    pub fn directReturn(payload: []const u8) []const u8 {
        transcript.caught_payload = payload;
        return payload;
    }
};

const transcript = struct {
    threadlocal var body_before_throw: bool = false;
    threadlocal var caught_payload: []const u8 = "";
};

/// Write the exception-family transcript through the lexical front door.
pub fn run(writer: anytype) anyerror!void {
    var runtime = shift.Runtime.init(std.heap.page_allocator);
    defer runtime.deinit();

    try writer.writeAll("branch=pass\n");
    const ok = try shift.with(&runtime, .{
        .exception = shift.effect.exception.use([]const u8, catch_policy),
    }, struct {
        /// Return normally through the exception scope.
        pub fn body(_: anytype) ![]const u8 {
            return "result=ok";
        }
    });
    try writer.writeAll("body-pass\n");
    try writer.print("final={s}\n", .{ok.value});

    try writer.writeAll("branch=throw\n");
    transcript.body_before_throw = false;
    transcript.caught_payload = "";
    const thrown = try shift.with(&runtime, .{
        .exception = shift.effect.exception.use([]const u8, catch_policy),
    }, struct {
        /// Throw once through the exception scope.
        pub fn body(eff: anytype) ![]const u8 {
            transcript.body_before_throw = true;
            try eff.exception.throw("result=boom");
        }
    });
    if (transcript.body_before_throw) try writer.writeAll("body-before-throw\n");
    try writer.print("catch={s}\n", .{transcript.caught_payload});
    try writer.print("final={s}\n", .{thrown.value});
}

/// Run the exception family example.
pub fn main() anyerror!void {
    var stdout_buffer: [512]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    const stdout = &stdout_writer.interface;
    try run(stdout);
    try stdout.flush();
}
