const shift = @import("shift");
const std = @import("std");

const NoError = error{};

/// Write the algebraic artifact-search transcript through the lexical front door.
pub fn run(writer: anytype) anyerror!void {
    var runtime = shift.Runtime.init(std.heap.page_allocator);
    defer runtime.deinit();
    var output_buffer: [256]u8 = undefined;
    var output_fba = std.heap.FixedBufferAllocator.init(&output_buffer);

    const result = try shift.with(&runtime, .{
        .reader = shift.effect.reader.use(NoError, "artifact-search"),
        .writer = shift.effect.writer.use([]const u8, NoError, output_fba.allocator()),
    }, struct {
        /// Read the query and emit the canonical artifact-search transcript fields.
        pub fn body(eff: anytype) shift.ResetError(NoError)!i32 {
            const query = try eff.reader.ask();
            if (!std.mem.eql(u8, query, "artifact-search")) unreachable;
            try eff.writer.tell("query=artifact-search");
            try eff.writer.tell("messages=1");
            try eff.writer.tell("tool_calls=0");
            try eff.writer.tell("memory_blocks=1");
            try eff.writer.tell("opencode_source=jsonl");
            return 3;
        }
    });

    for (result.outputs.writer) |item| {
        try writer.print("{s}\n", .{item});
    }
    try writer.print("total={d}\n", .{result.value});
}

/// Run the algebraic artifact-search example.
pub fn main() anyerror!void {
    var stdout_buffer: [512]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    const stdout = &stdout_writer.interface;
    try run(stdout);
    try stdout.flush();
}
