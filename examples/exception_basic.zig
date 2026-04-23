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

fn runPass(runtime: *shift.Runtime) ![]const u8 {
    const ok = try shift.with(runtime, .{
        .exception = shift.effect.exception.use([]const u8, catch_policy),
    }, struct {
        /// Run the non-throwing exception example body.
        pub fn body(eff: anytype) @TypeOf(exceptionPassBody(eff)) {
            return exceptionPassBody(eff);
        }
    });
    return ok.value;
}

fn runThrow(runtime: *shift.Runtime) ![]const u8 {
    const thrown = try shift.with(runtime, .{
        .exception = shift.effect.exception.use([]const u8, catch_policy),
    }, struct {
        /// Run the throwing exception example body.
        pub fn body(eff: anytype) @TypeOf(exceptionThrowBody(eff)) {
            return exceptionThrowBody(eff);
        }
    });
    return thrown.value;
}

/// Write the exception-family transcript through the lexical front door.
pub fn run(writer: anytype) anyerror!void {
    var runtime = shift.Runtime.init(std.heap.page_allocator);
    defer runtime.deinit();

    try writer.writeAll("branch=pass\n");
    const pass_result = try runPass(&runtime);
    try writer.writeAll("body-pass\n");
    try writer.print("final={s}\n", .{pass_result});

    try writer.writeAll("branch=throw\n");
    transcript.caught_payload = "";
    try writer.writeAll("body-before-throw\n");
    const thrown = try runThrow(&runtime);
    try writer.print("catch={s}\n", .{transcript.caught_payload});
    try writer.print("final={s}\n", .{thrown});
}

/// Run the exception family example.
pub fn main(init: std.process.Init) anyerror!void {
    var stdout_buffer: [512]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(init.io, &stdout_buffer);
    const stdout = &stdout_writer.interface;
    try run(stdout);
    try stdout.flush();
}
