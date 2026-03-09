const shift = @import("shift");
const std = @import("std");

const handler_spec = struct {
    /// Prompt tag.
    pub const tag = struct {};
    /// Outbound request type.
    pub const Request = union(enum) {
        abort: void,
        emit: []const u8,
    };
    /// Resume value type.
    pub const Resume = void;
    /// Final answer type.
    pub const Answer = []const u8;
    /// User error surface.
    pub const ErrorSet = error{Abort};
};

const demo = struct {
    var trace = [_][]const u8{ "", "", "" };
    var trace_count: usize = 0;
    var pending_message: []const u8 = "";

    fn emit(message: []const u8) shift.ResetError(handler_spec.ErrorSet)!void {
        pending_message = message;
        _ = try shift.shift(handler_spec, .{ .emit = message });
    }

    fn failWithAbort() shift.ResetError(handler_spec.ErrorSet)!void {
        _ = try shift.shift(handler_spec, .{ .abort = {} });
    }

    fn body() shift.ResetError(handler_spec.ErrorSet)!handler_spec.Answer {
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
    var step = try shift.reset(handler_spec, &runtime, demo.body);
    while (true) switch (step) {
        .complete => |value| {
            try stdout.print("result={s}\n", .{value});
            break;
        },
        .suspended => |*suspension| switch (suspension.request) {
            .emit => |message| {
                demo.trace[demo.trace_count] = message;
                demo.trace_count += 1;
                step = try suspension.resumeWith({});
            },
            .abort => {
                step = suspension.discontinue(error.Abort) catch |err| switch (err) {
                    error.Abort => {
                        try stdout.print("aborted=yes trace=[", .{});
                        for (demo.trace[0..demo.trace_count], 0..) |entry, index| {
                            if (index != 0) try stdout.print(", ", .{});
                            try stdout.print("{s}", .{entry});
                        }
                        try stdout.print("]\n", .{});
                        break;
                    },
                    else => return err,
                };
            },
        },
    };
    try stdout.flush();
}
