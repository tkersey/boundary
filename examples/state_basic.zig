const shift = @import("shift");
const std = @import("std");

const StateProgram = shift.Program(.{
    .state = shift.Decl.state(i32),
}, struct {
    /// Increment the front-door state once and return the canonical value witness.
    pub fn body(eff: anytype) !i32 {
        const before = try eff.state.get();
        try eff.state.set(before + 1);
        return before + (try eff.state.get());
    }
});

/// Write the state-effect transcript through the root front door.
pub fn run(writer: anytype) anyerror!void {
    var runtime = shift.Runtime.init(std.heap.page_allocator);
    defer runtime.deinit();

    const result = try shift.run(&runtime, StateProgram, .{
        .state = @as(i32, 5),
    });

    try writer.print("before=5\nafter=6\nfinal_state={d}\nvalue={d}\n", .{ result.outputs.state, result.value });
}

/// Run the state-effect example.
pub fn main() anyerror!void {
    var stdout_buffer: [256]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    const stdout = &stdout_writer.interface;
    try run(stdout);
    try stdout.flush();
}
