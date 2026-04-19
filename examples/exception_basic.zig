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
    threadlocal var caught_payload: []const u8 = "";
};

fn exceptionPassBody(_: anytype) anyerror![]const u8 {
    return "result=ok";
}

fn exceptionThrowBody(eff: anytype) anyerror![]const u8 {
    try eff.exception.throw("result=boom");
}

/// Write the exception-family transcript through the lexical front door.
pub fn run(writer: anytype) anyerror!void {
    var runtime = shift.Runtime.init(std.heap.page_allocator);
    defer runtime.deinit();

    try writer.writeAll("branch=pass\n");
    const ok = try shift.withAt(@src(), &runtime, .{
        .exception = shift.effect.exception.use([]const u8, catch_policy),
    }, shift.NamedBody("examples/exception_basic.zig", "exceptionPassBody", anyerror![]const u8, exceptionPassBody));
    try writer.writeAll("body-pass\n");
    try writer.print("final={s}\n", .{ok.value});

    try writer.writeAll("branch=throw\n");
    transcript.caught_payload = "";
    try writer.writeAll("body-before-throw\n");
    const thrown = try shift.withAt(@src(), &runtime, .{
        .exception = shift.effect.exception.use([]const u8, catch_policy),
    }, shift.NamedBody("examples/exception_basic.zig", "exceptionThrowBody", anyerror![]const u8, exceptionThrowBody));
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
