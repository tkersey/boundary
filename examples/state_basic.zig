const shift = @import("shift");
const std = @import("std");

const StateRow = shift.effects.state(i32);

const state_workflow = struct {
    /// Capability bundle for the state example.
    pub const Uses = shift.Uses(StateRow);

    /// Increment the front-door state once and return the canonical value witness.
    pub fn body(eff: anytype) anyerror!i32 {
        const before = try eff.state.get();
        try eff.state.set(before + 1);
        return before + (try eff.state.get());
    }
};

/// Write the state-effect transcript through the root front door.
pub fn run(writer: anytype) anyerror!void {
    var runtime = shift.Runtime.init(std.heap.page_allocator);
    defer runtime.deinit();

    const closed = shift.bind(state_workflow, .{
        .state = shift.handlers.state(@as(i32, 5)),
    });
    const result = try shift.run(&runtime, closed);

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
