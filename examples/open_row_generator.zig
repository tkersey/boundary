const ability = @import("ability");
const std = @import("std");

fn emitThird(eff: anytype) anyerror!void {
    try eff.state.set(3);
    try eff.writer.tell("yield=3");
}

fn emitSecond(eff: anytype) anyerror!void {
    try eff.state.set(2);
    try eff.writer.tell("yield=2");
    try emitThird(eff);
}

fn emitFirst(eff: anytype) anyerror!void {
    try eff.state.set(1);
    try eff.writer.tell("yield=1");
    try emitSecond(eff);
}

fn generatorBody(eff: anytype) anyerror!i32 {
    try emitFirst(eff);
    const final = try eff.state.get();
    return final;
}

fn runWithAllocator(writer: anytype, allocator: std.mem.Allocator) anyerror!void {
    var runtime = ability.Runtime.init(allocator);
    defer runtime.deinit();

    const result = try ability.with(&runtime, .{
        .state = ability.effect.state.use(@as(i32, 0)),
        .writer = ability.effect.writer.use([]const u8, allocator),
    }, struct {
        /// Run the generator example body through the lexical front door.
        pub fn body(eff: anytype) @TypeOf(generatorBody(eff)) {
            return generatorBody(eff);
        }
    });
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
pub fn main(init: std.process.Init) anyerror!void {
    var stdout_buffer: [256]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(init.io, &stdout_buffer);
    const stdout = &stdout_writer.interface;
    try run(stdout);
    try stdout.flush();
}
