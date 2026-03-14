const shift = @import("shift");
const std = @import("std");

const NoError = error{};
const ExceptionInstance = shift.effect.exception.Instance([]const u8, NoError);

fn runPass(writer: anytype) anyerror!void {
    const catcher = struct {
        /// Preserve the body answer when no throw happens.
        pub fn directReturn(payload: []const u8) []const u8 {
            return payload;
        }
    };
    const demo = struct {
        /// Complete normally without throwing.
        pub fn body(comptime Cap: type, _: anytype) shift.ResetError(NoError)![]const u8 {
            _ = Cap;
            return "result=ok";
        }
    };

    var runtime = shift.Runtime.init(std.heap.page_allocator, .{});
    defer runtime.deinit();
    var instance = ExceptionInstance.init();
    const answer = try shift.effect.exception.handle([]const u8, &runtime, &instance, catcher, demo);
    try writer.writeAll("body-pass\n");
    try writer.print("final={s}\n", .{answer});
}

fn runThrow(writer: anytype) anyerror!void {
    const catcher = struct {
        var transcript = [_][]const u8{ "", "" };
        var transcript_len: usize = 0;

        fn note(message: []const u8) void {
            transcript[transcript_len] = message;
            transcript_len += 1;
        }

        /// Record and recover the thrown payload.
        pub fn directReturn(payload: []const u8) []const u8 {
            _ = payload;
            note("catch=result=boom");
            return "result=boom";
        }
    };
    const demo = struct {
        fn note(message: []const u8) void {
            catcher.note(message);
        }

        /// Throw once through the public exception helper.
        pub fn body(comptime Cap: type, ctx: anytype) shift.ResetError(NoError)![]const u8 {
            note("body-before-throw");
            try shift.effect.exception.throw(Cap, ctx, "result=boom");
        }
    };

    var runtime = shift.Runtime.init(std.heap.page_allocator, .{});
    defer runtime.deinit();
    var instance = ExceptionInstance.init();
    catcher.transcript_len = 0;
    const answer = try shift.effect.exception.handle([]const u8, &runtime, &instance, catcher, demo);
    for (catcher.transcript[0..catcher.transcript_len]) |line| try writer.print("{s}\n", .{line});
    try writer.print("final={s}\n", .{answer});
}

/// Write both exception-family branches in one example transcript.
pub fn run(writer: anytype) anyerror!void {
    try writer.writeAll("branch=pass\n");
    try runPass(writer);
    try writer.writeAll("branch=throw\n");
    try runThrow(writer);
}

/// Run the exception family example using only the public effect surface.
pub fn main() anyerror!void {
    var stdout_buffer: [512]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    const stdout = &stdout_writer.interface;
    try run(stdout);
    try stdout.flush();
}
