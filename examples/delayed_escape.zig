const shift = @import("shift");
const std = @import("std");

const main_prompt_t = shift.Prompt(usize, usize);
const state = struct {
    var main_prompt = main_prompt_t.init();
};

const machine = struct {
    pub const Answer = usize;
    pub const Error = error{};
    pub const Frame = union(enum) {
        after_first: void,
        after_second: void,
        start: void,
    };
    pub const Resume = union(enum) {
        first: usize,
        second: usize,
        start: void,
    };
    pub const Suspend = union(enum) {
        first: struct {
            next: Frame,
            prompt: *main_prompt_t,
            request: usize,
        },
        second: struct {
            next: Frame,
            prompt: *main_prompt_t,
            request: usize,
        },
    };

    pub fn step(frame: Frame, resume_value: Resume) (shift.Error || Error)!shift.Step(Frame, Suspend, Answer) {
        return switch (frame) {
            .start => .{
                .@"suspend" = .{
                    .first = .{
                        .next = .{ .after_first = {} },
                        .prompt = &state.main_prompt,
                        .request = 41,
                    },
                },
            },
            .after_first => switch (resume_value) {
                .first => |value| .{
                    .@"suspend" = .{
                        .second = .{
                            .next = .{ .after_second = {} },
                            .prompt = &state.main_prompt,
                            .request = value + 1,
                        },
                    },
                },
                else => unreachable,
            },
            .after_second => switch (resume_value) {
                .second => |value| .{ .complete = value + 1 },
                else => unreachable,
            },
        };
    }
};

pub fn main() anyerror!void {
    var runtime = shift.Runtime.init(std.heap.page_allocator, .{});
    defer runtime.deinit();

    var stdout_buffer: [256]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    const stdout = &stdout_writer.interface;

    var outcome = try shift.run(machine, &runtime, .{ .start = {} });
    var escaped: ?shift.EscapedOwner(machine) = null;

    switch (outcome) {
        .complete => unreachable,
        .pending => |*pending| {
            const suspension = pending.@"suspend"();
            switch (suspension) {
                .first => |call| {
                    try stdout.print("first={d}\n", .{call.request});
                    escaped = try pending.escape();
                },
                else => unreachable,
            }
        },
    }

    outcome = try escaped.?.@"resume"(.{ .first = 41 });
    switch (outcome) {
        .complete => unreachable,
        .pending => |*pending| {
            const suspension = pending.@"suspend"();
            switch (suspension) {
                .second => |call| {
                    try stdout.print("second={d}\n", .{call.request});
                    outcome = try pending.@"resume"(.{ .second = call.request });
                },
                else => unreachable,
            }
        },
    }

    switch (outcome) {
        .complete => |answer| try stdout.print("answer={d}\n", .{answer}),
        .pending => unreachable,
    }
    try stdout.flush();
}
