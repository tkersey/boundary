const ability = @import("ability");
const std = @import("std");

fn stateBody(eff: anytype) anyerror!i32 {
    const before = try eff.state.get();
    try eff.state.set(before + 1);
    const after = try eff.state.get();
    return before + after;
}

/// Write the state-effect transcript through the lexical front door.
pub fn run(writer: anytype) anyerror!void {
    var runtime = ability.Runtime.init(std.heap.page_allocator);
    defer runtime.deinit();

    const result = try ability.with(&runtime, .{
        .state = ability.effect.state.use(@as(i32, 5)),
    }, struct {
        /// Run the state example body through the lexical front door.
        pub fn body(eff: anytype) @TypeOf(stateBody(eff)) {
            return stateBody(eff);
        }
    });

    try writer.print("before=5\nafter=6\nfinal_state={d}\nvalue={d}\n", .{ result.outputs.state, result.value });
}

/// Run the state-effect example.
pub fn main(init: std.process.Init) anyerror!void {
    var stdout_buffer: [256]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(init.io, &stdout_buffer);
    const stdout = &stdout_writer.interface;
    try run(stdout);
    try stdout.flush();
}
