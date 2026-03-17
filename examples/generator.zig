const shift = @import("shift");
const std = @import("std");

const NoError = error{};

/// Write the generator transcript through the lexical front door.
pub fn run(writer: anytype) anyerror!void {
    var runtime = shift.Runtime.init(std.heap.page_allocator);
    defer runtime.deinit();
    var output_buffer: [256]u8 = undefined;
    var output_fba = std.heap.FixedBufferAllocator.init(&output_buffer);

    const result = try shift.with(&runtime, .{
        .writer = shift.effect.writer.use([]const u8, NoError, output_fba.allocator()),
        .state = shift.effect.state.use(NoError, @as(i32, 0)),
    }, struct {
        /// Emit three yielded values and return the final counter.
        pub fn body(eff: anytype) shift.ResetError(NoError)!i32 {
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
    });

    for (result.outputs.writer) |item| {
        try writer.print("{s}\n", .{item});
    }
    try writer.print("done={d}\n", .{result.value});
}

/// Run the generator example.
pub fn main() anyerror!void {
    var stdout_buffer: [256]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    const stdout = &stdout_writer.interface;
    try run(stdout);
    try stdout.flush();
}
