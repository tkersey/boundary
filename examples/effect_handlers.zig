const example_driver = @import("example_driver");
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

const driver = struct {
    fn handle(_: *@This(), request: handler_spec.Request) anyerror!example_driver.Decision(handler_spec) {
        return switch (request) {
            .emit => |message| blk: {
                demo.trace[demo.trace_count] = message;
                demo.trace_count += 1;
                break :blk .{ .resume_value = {} };
            },
            .abort => .{ .discontinue = error.Abort },
        };
    }
};

/// Run the discontinue example.
pub fn main() anyerror!void {
    var runtime = shift.Runtime.init(std.heap.page_allocator, .{});
    defer runtime.deinit();

    var stdout_buffer: [256]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    const stdout = &stdout_writer.interface;
    var loop_driver: driver = .{};
    const outcome = example_driver.run(handler_spec, &runtime, demo.body, &loop_driver, driver.handle) catch |err| switch (err) {
        error.Abort => {
            try stdout.print("aborted=yes trace=[", .{});
            for (demo.trace[0..demo.trace_count], 0..) |entry, index| {
                if (index != 0) try stdout.print(", ", .{});
                try stdout.print("{s}", .{entry});
            }
            try stdout.print("]\n", .{});
            try stdout.flush();
            return;
        },
        else => return err,
    };
    switch (outcome) {
        .complete => |value| {
            try stdout.print("result={s}\n", .{value});
        },
        .cancelled => unreachable,
    }
    try stdout.flush();
}
