const shift = @import("shift");
const std = @import("std");

const tag = struct {};
const DemoError = error{Abort};

const demo = struct {
    var trace = [_][]const u8{ "", "", "" };
    var trace_count: usize = 0;
    var pending_message: []const u8 = "";

    fn emit(message: []const u8) shift.ResetError(DemoError)!void {
        pending_message = message;
        _ = try shift.shift(void, tag, []const u8, DemoError, handleEmit);
    }

    fn failWithAbort() shift.ResetError(DemoError)!void {
        _ = try shift.shift(void, tag, []const u8, DemoError, handleAbort);
    }

    fn handleEmit(k: *shift.Continuation(void, tag, []const u8, DemoError)) shift.ResetError(DemoError)![]const u8 {
        trace[trace_count] = pending_message;
        trace_count += 1;
        return try k.resumeWith({});
    }

    fn handleAbort(k: *shift.Continuation(void, tag, []const u8, DemoError)) shift.ResetError(DemoError)![]const u8 {
        return k.discontinue(error.Abort);
    }

    fn body() shift.ResetError(DemoError)![]const u8 {
        trace_count = 0;
        try emit("enter");
        try emit("before-abort");
        try failWithAbort();
        try emit("unreachable");
        return "ok";
    }
};

/// Run the discontinue example.
pub fn main() anyerror!void {
    var runtime = shift.Runtime.init(std.heap.page_allocator, .{});
    defer runtime.deinit();

    var stdout_buffer: [256]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    const stdout = &stdout_writer.interface;
    const result = shift.reset(tag, []const u8, DemoError, &runtime, demo.body);
    if (result) |value| {
        try stdout.print("result={s}\n", .{value});
    } else |err| switch (err) {
        error.Abort => {
            try stdout.print("aborted=yes trace=[", .{});
            for (demo.trace[0..demo.trace_count], 0..) |entry, index| {
                if (index != 0) try stdout.print(", ", .{});
                try stdout.print("{s}", .{entry});
            }
            try stdout.print("]\n", .{});
        },
        else => return err,
    }
    try stdout.flush();
}
