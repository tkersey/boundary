const shift = @import("shift");
const std = @import("std");

const generator_row = shift.mergeRows(.{
    shift.effects.state(i32),
    shift.effects.writer([]const u8),
});

const generator_workflow = struct {
    /// Capability bundle for the generator example.
    pub const Uses = shift.Uses(generator_row);

    /// Emit three yielded values and return the final counter.
    pub fn body(eff: anytype) anyerror!i32 {
        while (true) {
            const current = try eff.state.get();
            if (current == 3) return current;
            const next = current + 1;
            try eff.state.set(next);
            const line = switch (next) {
                1 => "yield=1",
                2 => "yield=2",
                3 => "yield=3",
                else => unreachable,
            };
            try eff.writer.tell(line);
        }
    }
};

fn runWithAllocator(writer: anytype, allocator: std.mem.Allocator) anyerror!void {
    var runtime = shift.Runtime.init(allocator);
    defer runtime.deinit();

    const closed = shift.bind(generator_workflow, .{
        .state = shift.handlers.state(@as(i32, 0)),
        .writer = shift.handlers.writer([]const u8, allocator),
    });
    const result = try shift.run(&runtime, closed);
    defer allocator.free(result.outputs.writer);

    for (result.outputs.writer) |item| {
        try writer.print("{s}\n", .{item});
    }
    try writer.print("done={d}\n", .{result.value});
}

/// Render the generator transcript.
pub fn run(writer: anytype) anyerror!void {
    try runWithAllocator(writer, std.heap.page_allocator);
}

/// Run the generator example on stdout.
pub fn main() anyerror!void {
    var stdout_buffer: [256]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    const stdout = &stdout_writer.interface;
    try run(stdout);
    try stdout.flush();
}
