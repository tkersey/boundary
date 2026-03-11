const shift = @import("shift");
const std = @import("std");

const iterations: usize = 50_000;
const samples_per_run: usize = 5;
const warmup_iterations: usize = 20_000;

const Prompt = shift.Prompt(usize, usize);
const state = struct {
    var prompt = Prompt.init();
};

const Machine = struct {
    pub const Answer = usize;
    pub const Error = error{};
    pub const Frame = union(enum) {
        start: void,
        after_first: void,
        after_second: void,
    };
    pub const Resume = union(enum) {
        start: void,
        main: usize,
    };
    pub const Suspend = union(enum) {
        main: struct { prompt: *Prompt, request: usize, next: Frame },
    };

    pub fn step(frame: Frame, resume_value: Resume) (shift.Error || Error)!shift.Step(Frame, Suspend, Answer) {
        return switch (frame) {
            .start => switch (resume_value) {
                .start => .{ .@"suspend" = .{ .main = .{ .prompt = &state.prompt, .request = current_value, .next = .{ .after_first = {} } } } },
                else => unreachable,
            },
            .after_first => switch (resume_value) {
                .main => |value| .{ .@"suspend" = .{ .main = .{ .prompt = &state.prompt, .request = value + 1, .next = .{ .after_second = {} } } } },
                else => unreachable,
            },
            .after_second => switch (resume_value) {
                .main => |value| .{ .complete = value + 1 },
                else => unreachable,
            },
        };
    }
};

var current_value: usize = 0;

fn runSample() !struct { elapsed: u64, checksum: usize } {
    var runtime = shift.Runtime.init(std.heap.smp_allocator, .{});
    defer runtime.deinit();

    var warmup_i: usize = 0;
    while (warmup_i < warmup_iterations) : (warmup_i += 1) {
        current_value = warmup_i;
        var outcome = try shift.run(Machine, &runtime, .{ .start = {} });
        switch (outcome) {
            .complete => unreachable,
            .pending => |*pending| {
                var escaped = try pending.escape();
                outcome = try escaped.@"resume"(.{ .main = current_value });
            },
        }
        switch (outcome) {
            .complete => unreachable,
            .pending => |*pending| outcome = try pending.@"resume"(.{ .main = current_value + 1 }),
        }
        switch (outcome) {
            .complete => {},
            .pending => unreachable,
        }
    }

    var timer = try std.time.Timer.start();
    var sum: usize = 0;

    var i: usize = 0;
    while (i < iterations) : (i += 1) {
        current_value = i;
        var outcome = try shift.run(Machine, &runtime, .{ .start = {} });
        switch (outcome) {
            .complete => unreachable,
            .pending => |*pending| {
                var escaped = try pending.escape();
                outcome = try escaped.@"resume"(.{ .main = current_value });
            },
        }
        switch (outcome) {
            .complete => unreachable,
            .pending => |*pending| outcome = try pending.@"resume"(.{ .main = current_value + 1 }),
        }
        switch (outcome) {
            .complete => |answer| sum += answer,
            .pending => unreachable,
        }
    }

    return .{
        .elapsed = timer.read(),
        .checksum = sum,
    };
}

fn sortSamples(samples: *[samples_per_run]u64) void {
    var left_index: usize = 0;
    while (left_index < samples.len) : (left_index += 1) {
        var right_index: usize = left_index + 1;
        while (right_index < samples.len) : (right_index += 1) {
            if (samples[right_index] < samples[left_index]) {
                const tmp = samples[left_index];
                samples[left_index] = samples[right_index];
                samples[right_index] = tmp;
            }
        }
    }
}

pub fn main() anyerror!void {
    var samples = [_]u64{0} ** samples_per_run;
    var checksum: usize = 0;

    for (&samples, 0..) |*slot, sample_index| {
        const result = try runSample();
        slot.* = result.elapsed;
        if (sample_index == 0) {
            checksum = result.checksum;
        } else {
            std.debug.assert(checksum == result.checksum);
        }
    }

    var sorted = samples;
    sortSamples(&sorted);

    var stdout_buffer: [512]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    const stdout = &stdout_writer.interface;
    try stdout.print(
        "samples={d} warmup_iterations={d} iterations={d} min_ns={d} median_ns={d} max_ns={d} checksum={d} sample_ns=[",
        .{ samples_per_run, warmup_iterations, iterations, sorted[0], sorted[sorted.len / 2], sorted[sorted.len - 1], checksum },
    );
    for (samples, 0..) |sample, sample_index| {
        if (sample_index != 0) try stdout.print(",", .{});
        try stdout.print("{d}", .{sample});
    }
    try stdout.print("]\n", .{});
    try stdout.flush();
}
