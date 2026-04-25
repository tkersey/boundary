const ability = @import("ability");
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
    var runtime = ability.Runtime.init(std.heap.page_allocator);
    defer runtime.deinit();
    transcript.handler_line = "";

    const result = try ability.with(&runtime, .{
        .exception = ability.effect.exception.use([]const u8, catch_policy),
    }, struct {
        /// Run the early-exit example body through the lexical front door.
        pub fn body(eff: anytype) @TypeOf(earlyExitBody(eff)) {
            return earlyExitBody(eff);
        }
    });

    try writer.print("{s}\n", .{transcript.handler_line});
    try writer.print("final={s}\n", .{result.value});
}

/// Run the direct-return example.
pub fn main(init: std.process.Init) anyerror!void {
    var stdout_buffer: [256]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(init.io, &stdout_buffer);
    const stdout = &stdout_writer.interface;
    try run(stdout);
    try stdout.flush();
}
