const shift = @import("shift");
const std = @import("std");

fn stateBody(eff: anytype) anyerror!i32 {
    const before = try eff.state.get();
    try eff.state.set(before + 1);
    const after = try eff.state.get();
    return before + after;
}

/// Write the state-effect transcript through the lexical front door.
pub fn run(writer: anytype) anyerror!void {
    var runtime = shift.Runtime.init(std.heap.page_allocator);
    defer runtime.deinit();

    const result = try shift.with(@src(), &runtime, .{
        .state = shift.effect.state.use(@as(i32, 5)),
    }, shift.NamedBody("examples/state_basic.zig", "stateBody", anyerror!i32, stateBody));

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
