const shift = @import("shift");
const std = @import("std");

const inner_prompt_t = shift.Prompt([]const u8, void);
const outer_prompt_t = shift.Prompt([]const u8, void);
const state = struct {
    var inner_prompt = inner_prompt_t.init();
    var outer_prompt = outer_prompt_t.init();
};

const machine = struct {
    pub const Answer = void;
    pub const Error = error{};
    pub const Frame = union(enum) {
        after_inner: void,
        after_outer: void,
        start: void,
    };
    pub const Resume = union(enum) {
        inner: void,
        outer: void,
        start: void,
    };
    pub const Suspend = union(enum) {
        inner: struct {
            next: Frame,
            prompt: *inner_prompt_t,
            request: []const u8,
        },
        outer: struct {
            next: Frame,
            prompt: *outer_prompt_t,
            request: []const u8,
        },
    };

    pub fn step(frame: Frame, resume_value: Resume) (shift.Error || Error)!shift.Step(Frame, Suspend, Answer) {
        return switch (frame) {
            .start => .{
                .@"suspend" = .{
                    .outer = .{
                        .next = .{ .after_outer = {} },
                        .prompt = &state.outer_prompt,
                        .request = "outer",
                    },
                },
            },
            .after_outer => switch (resume_value) {
                .outer => .{
                    .@"suspend" = .{
                        .inner = .{
                            .next = .{ .after_inner = {} },
                            .prompt = &state.inner_prompt,
                            .request = "inner",
                        },
                    },
                },
                else => unreachable,
            },
            .after_inner => switch (resume_value) {
                .inner => .{ .complete = {} },
                else => unreachable,
            },
        };
    }
};

pub fn main() anyerror!void {
    var runtime = shift.Runtime.init(std.heap.page_allocator, .{});
    defer runtime.deinit();

    var seen_outer: []const u8 = "";
    var seen_inner: []const u8 = "";
    var outcome = try shift.run(machine, &runtime, .{ .start = {} });
    while (true) switch (outcome) {
        .complete => break,
        .pending => |*pending| {
            const suspension = pending.@"suspend"();
            switch (suspension) {
                .inner => |call| {
                    seen_inner = call.request;
                    outcome = try pending.@"resume"(.{ .inner = {} });
                },
                .outer => |call| {
                    seen_outer = call.request;
                    outcome = try pending.@"resume"(.{ .outer = {} });
                },
            }
        },
    };

    var stdout_buffer: [256]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    const stdout = &stdout_writer.interface;
    try stdout.print("outer={s}\ninner={s}\n", .{ seen_outer, seen_inner });
    try stdout.flush();
}
