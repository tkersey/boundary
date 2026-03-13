const shift = @import("shift");
const std = @import("std");

const NoError = error{};
const DemoPrompt = shift.Prompt(.direct_return, []const u8, []const u8, NoError);

pub fn run(writer: anytype) anyerror!void {
    const demo = struct {
        var prompt_ptr: ?*const DemoPrompt = null;
        var transcript = [_][]const u8{ "", "" };
        var transcript_len: usize = 0;

        fn note(message: []const u8) void {
            transcript[transcript_len] = message;
            transcript_len += 1;
        }

        const handle = struct {
            pub fn directReturn() []const u8 {
                note("handler-direct-return");
                return "result=early";
            }
        };

        fn body() shift.ResetError(NoError)![]const u8 {
            _ = try shift.shift(void, prompt_ptr.?, handle);
            return "result=late";
        }
    };

    var runtime = shift.Runtime.init(std.heap.page_allocator, .{});
    defer runtime.deinit();
    var prompt = DemoPrompt.init();
    demo.prompt_ptr = &prompt;
    demo.transcript_len = 0;

    const answer = try shift.reset(&runtime, &prompt, demo.body);
    for (demo.transcript[0..demo.transcript_len]) |line| try writer.print("{s}\n", .{line});
    try writer.print("final={s}\n", .{answer});
}

/// Run the direct-return example using only the public shift surface.
pub fn main() anyerror!void {
    var stdout_buffer: [256]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    const stdout = &stdout_writer.interface;
    try run(stdout);
    try stdout.flush();
}
