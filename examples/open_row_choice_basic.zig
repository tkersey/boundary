const ability = @import("ability");
const std = @import("std");

const transcript = struct {
    threadlocal var items = [_][]const u8{ "", "", "", "", "", "", "", "" };
    threadlocal var len: usize = 0;

    fn note(message: []const u8) void {
        items[len] = message;
        len += 1;
    }
};

const PickerHandler = struct {
    branch: enum { resume_with, return_now },

    /// Choose the configured branch.
    pub fn pick(self: *@This(), payload: i32) !ability.effect.choice.Decision(i32, []const u8) {
        return switch (self.branch) {
            .return_now => blk: {
                transcript.note("policy-return-now");
                break :blk ability.effect.choice.Decision(i32, []const u8).returnNow("result=early");
            },
            .resume_with => blk: {
                transcript.note("policy-resume");
                break :blk ability.effect.choice.Decision(i32, []const u8).resumeWith(payload);
            },
        };
    }

    /// Finalize the configured choice answer.
    pub fn afterPick(self: *@This(), answer: []const u8) ![]const u8 {
        if (self.branch == .resume_with) {
            transcript.note("body-after-pick");
            transcript.note("policy-after-resume");
        }
        return answer;
    }
};

const Picker = ability.effect.Define(.{
    .state_type = void,
    .ops = .{
        ability.effect.ops.Choice("pick", i32, i32),
    },
});

fn choiceReturnNowBody(eff: anytype) anyerror![]const u8 {
    return try eff.picker.pick.perform(41, struct {
        /// Resume the continuation with the canonical final answer.
        pub fn apply(_: i32, _: anytype) ![]const u8 {
            return "unused";
        }
    });
}

fn choiceResumeBody(eff: anytype) anyerror![]const u8 {
    return try eff.picker.pick.perform(41, struct {
        /// Resume the continuation with the canonical final answer.
        pub fn apply(_: i32, _: anytype) ![]const u8 {
            return "answer=42";
        }
    });
}

fn runReturnNow(runtime: *ability.Runtime) ![]const u8 {
    const early = try ability.with(runtime, .{
        .picker = Picker.use(.{ .handler = PickerHandler{ .branch = .return_now } }),
    }, struct {
        /// Run the return-now choice example body.
        pub fn body(eff: anytype) @TypeOf(choiceReturnNowBody(eff)) {
            return choiceReturnNowBody(eff);
        }
    });
    return early.value;
}

fn runResume(runtime: *ability.Runtime) ![]const u8 {
    const resumed = try ability.with(runtime, .{
        .picker = Picker.use(.{ .handler = PickerHandler{ .branch = .resume_with } }),
    }, struct {
        /// Run the resumed choice example body.
        pub fn body(eff: anytype) @TypeOf(choiceResumeBody(eff)) {
            return choiceResumeBody(eff);
        }
    });
    return resumed.value;
}

/// Render the choice example transcript.
pub fn run(writer: anytype) anyerror!void {
    var runtime = ability.Runtime.init(std.heap.page_allocator);
    defer runtime.deinit();

    try writer.writeAll("branch=return_now\n");
    transcript.len = 0;
    const early = try runReturnNow(&runtime);
    for (transcript.items[0..transcript.len]) |item| {
        try writer.print("{s}\n", .{item});
    }
    try writer.print("final={s}\n", .{early});

    try writer.writeAll("branch=resume_with\n");
    transcript.len = 0;
    const resumed = try runResume(&runtime);
    for (transcript.items[0..transcript.len]) |item| {
        try writer.print("{s}\n", .{item});
    }
    try writer.print("final={s}\n", .{resumed});
}

/// Run the choice example on stdout.
pub fn main(init: std.process.Init) anyerror!void {
    var stdout_buffer: [256]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(init.io, &stdout_buffer);
    const stdout = &stdout_writer.interface;
    try run(stdout);
    try stdout.flush();
}
