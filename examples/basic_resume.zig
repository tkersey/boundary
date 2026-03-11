const shift = @import("shift");
const std = @import("std");

const input_prompt = shift.Prompt(i32, i32);
const state = struct {
    var prompt = input_prompt.init();
};

const machine = struct {
    pub const Answer = i32;
    pub const Error = error{};
    pub const Frame = union(enum) {
        after_input: void,
        start: void,
    };
    pub const Resume = union(enum) {
        input: i32,
        start: void,
    };
    pub const Suspend = union(enum) {
        input: struct {
            next: Frame,
            prompt: *input_prompt,
            request: i32,
        },
    };

    pub fn step(frame: Frame, resume_value: Resume) (shift.Error || Error)!shift.Step(Frame, Suspend, Answer) {
        return switch (frame) {
            .start => .{
                .@"suspend" = .{
                    .input = .{
                        .next = .{ .after_input = {} },
                        .prompt = &state.prompt,
                        .request = 41,
                    },
                },
            },
            .after_input => switch (resume_value) {
                .input => |value| .{ .complete = value + 1 },
                else => unreachable,
            },
        };
    }
};

pub fn main() anyerror!void {
    var runtime = shift.Runtime.init(std.heap.page_allocator, .{});
    defer runtime.deinit();

    var outcome = try shift.run(machine, &runtime, .{ .start = {} });
    while (true) switch (outcome) {
        .complete => |answer| {
            var stdout_buffer: [128]u8 = undefined;
            var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
            const stdout = &stdout_writer.interface;
            try stdout.print("answer={d}\n", .{answer});
            try stdout.flush();
            break;
        },
        .pending => |*pending| {
            const suspension = pending.@"suspend"();
            switch (suspension) {
                .input => |call| outcome = try pending.@"resume"(.{ .input = call.request }),
            }
        },
    };
}
