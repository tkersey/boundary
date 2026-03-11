const shift = @import("shift");
const std = @import("std");

fn expect(ok: bool) error{SmokeCheckFailed}!void {
    if (!ok) return error.SmokeCheckFailed;
}

fn expectError(comptime expected: anyerror, actual: anytype) error{SmokeCheckFailed}!void {
    _ = actual catch |err| {
        if (err == expected) return;
        return error.SmokeCheckFailed;
    };
    return error.SmokeCheckFailed;
}

fn basicResume() !void {
    const prompt_t = shift.Prompt(i32, i32);
    const state = struct {
        var prompt = prompt_t.init();
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
            input: struct { next: Frame, prompt: *prompt_t, request: i32 },
        };

        pub fn step(frame: Frame, resume_value: Resume) (shift.Error || Error)!shift.Step(Frame, Suspend, Answer) {
            return switch (frame) {
                .start => .{ .@"suspend" = .{ .input = .{ .next = .{ .after_input = {} }, .prompt = &state.prompt, .request = 41 } } },
                .after_input => switch (resume_value) {
                    .input => |value| .{ .complete = value + 1 },
                    else => unreachable,
                },
            };
        }
    };

    var runtime = shift.Runtime.init(std.heap.page_allocator, .{});
    defer runtime.deinit();

    var outcome = try shift.run(machine, &runtime, .{ .start = {} });
    while (true) switch (outcome) {
        .complete => |answer| {
            try expect(answer == 42);
            return;
        },
        .pending => |*pending| {
            const suspension = pending.@"suspend"();
            switch (suspension) {
                .input => |call| outcome = try pending.@"resume"(.{ .input = call.request }),
            }
        },
    };
}

fn delayedEscape() !void {
    const prompt_t = shift.Prompt(usize, usize);
    const state = struct {
        var prompt = prompt_t.init();
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
            first: struct { next: Frame, prompt: *prompt_t, request: usize },
            second: struct { next: Frame, prompt: *prompt_t, request: usize },
        };

        pub fn step(frame: Frame, resume_value: Resume) (shift.Error || Error)!shift.Step(Frame, Suspend, Answer) {
            return switch (frame) {
                .start => .{ .@"suspend" = .{ .first = .{ .next = .{ .after_first = {} }, .prompt = &state.prompt, .request = 41 } } },
                .after_first => switch (resume_value) {
                    .first => |value| .{ .@"suspend" = .{ .second = .{ .next = .{ .after_second = {} }, .prompt = &state.prompt, .request = value + 1 } } },
                    else => unreachable,
                },
                .after_second => switch (resume_value) {
                    .second => |value| .{ .complete = value + 1 },
                    else => unreachable,
                },
            };
        }
    };

    var runtime = shift.Runtime.init(std.heap.page_allocator, .{});
    defer runtime.deinit();

    var outcome = try shift.run(machine, &runtime, .{ .start = {} });
    switch (outcome) {
        .complete => unreachable,
        .pending => |*pending| {
            var escaped = try pending.escape();
            outcome = try escaped.@"resume"(.{ .first = 41 });
        },
    }
    switch (outcome) {
        .complete => unreachable,
        .pending => |*pending| {
            const suspension = pending.@"suspend"();
            switch (suspension) {
                .second => |call| outcome = try pending.@"resume"(.{ .second = call.request }),
                else => unreachable,
            }
        },
    }
    switch (outcome) {
        .complete => |answer| try expect(answer == 43),
        .pending => unreachable,
    }
}

fn multiPrompt() !void {
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
            inner: struct { next: Frame, prompt: *inner_prompt_t, request: []const u8 },
            outer: struct { next: Frame, prompt: *outer_prompt_t, request: []const u8 },
        };

        pub fn step(frame: Frame, resume_value: Resume) (shift.Error || Error)!shift.Step(Frame, Suspend, Answer) {
            return switch (frame) {
                .start => .{ .@"suspend" = .{ .outer = .{ .next = .{ .after_outer = {} }, .prompt = &state.outer_prompt, .request = "outer" } } },
                .after_outer => switch (resume_value) {
                    .outer => .{ .@"suspend" = .{ .inner = .{ .next = .{ .after_inner = {} }, .prompt = &state.inner_prompt, .request = "inner" } } },
                    else => unreachable,
                },
                .after_inner => switch (resume_value) {
                    .inner => .{ .complete = {} },
                    else => unreachable,
                },
            };
        }
    };

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
    try expect(std.mem.eql(u8, seen_outer, "outer"));
    try expect(std.mem.eql(u8, seen_inner, "inner"));
}

fn aliasRejection() !void {
    const prompt_t = shift.Prompt(i32, i32);
    const state = struct {
        var prompt = prompt_t.init();
        var prompt_alias = prompt_t.init();
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
            input: struct { next: Frame, prompt: *prompt_t, request: i32 },
        };

        pub fn step(frame: Frame, resume_value: Resume) (shift.Error || Error)!shift.Step(Frame, Suspend, Answer) {
            return switch (frame) {
                .start => .{ .@"suspend" = .{ .input = .{ .next = .{ .after_input = {} }, .prompt = &state.prompt, .request = 41 } } },
                .after_input => switch (resume_value) {
                    .input => |value| .{ .complete = value + 1 },
                    else => unreachable,
                },
            };
        }
    };
    const alias_machine = struct {
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
            input: struct { next: Frame, prompt: *prompt_t, request: i32 },
        };

        pub fn step(frame: Frame, resume_value: Resume) (shift.Error || Error)!shift.Step(Frame, Suspend, Answer) {
            return switch (frame) {
                .start => .{ .@"suspend" = .{ .input = .{ .next = .{ .after_input = {} }, .prompt = &state.prompt_alias, .request = 41 } } },
                .after_input => switch (resume_value) {
                    .input => |value| .{ .complete = value + 1 },
                    else => unreachable,
                },
            };
        }
    };

    var runtime = shift.Runtime.init(std.heap.page_allocator, .{});
    defer runtime.deinit();

    var outcome = try shift.run(machine, &runtime, .{ .start = {} });
    switch (outcome) {
        .complete => unreachable,
        .pending => |*pending| {
            var escaped = try pending.escape();
            var alias = escaped;
            outcome = try escaped.@"resume"(.{ .input = 41 });
            try expectError(error.OwnerAliased, alias.@"resume"(.{ .input = 41 }));
        },
    }
    switch (outcome) {
        .complete => |answer| try expect(answer == 42),
        .pending => unreachable,
    }

    state.prompt_alias = state.prompt;
    try expectError(error.PromptAliased, shift.run(alias_machine, &runtime, .{ .start = {} }));
}

pub fn main() anyerror!void {
    try basicResume();
    try delayedEscape();
    try multiPrompt();
    try aliasRejection();
}
