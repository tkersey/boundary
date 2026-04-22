const shift = @import("shift");
const std = @import("std");

const transcript = struct {
    threadlocal var items = [_][]const u8{ "", "", "", "", "", "" };
    threadlocal var len: usize = 0;

    fn note(message: []const u8) void {
        items[len] = message;
        len += 1;
    }
};

const resource_manager = struct {
    threadlocal var next_index: usize = 0;
    const resources = [_][]const u8{ "a", "b" };

    /// Acquire resources in the same order as the canonical example.
    pub fn acquire() []const u8 {
        const resource = resources[next_index];
        next_index += 1;
        transcript.items[transcript.len] = if (std.mem.eql(u8, resource, "a")) "acquire=a" else "acquire=b";
        transcript.len += 1;
        transcript.items[transcript.len] = if (std.mem.eql(u8, resource, "a")) "use=a" else "use=b";
        transcript.len += 1;
        return resource;
    }

    /// Release resources in the canonical LIFO order.
    pub fn release(resource: []const u8) void {
        transcript.items[transcript.len] = if (std.mem.eql(u8, resource, "a")) "release=a" else "release=b";
        transcript.len += 1;
    }
};

fn resourceBody(eff: anytype) anyerror![]const u8 {
    _ = try eff.resource.acquire();
    _ = try eff.resource.acquire();
    return "done";
}

/// Write the resource-effect transcript through the lexical front door.
pub fn run(writer: anytype) anyerror!void {
    var runtime = shift.Runtime.init(std.heap.page_allocator);
    defer runtime.deinit();
    resource_manager.next_index = 0;
    transcript.len = 0;

    const result = try shift.with(&runtime, .{
        .resource = shift.effect.resource.use([]const u8, resource_manager),
    }, struct {
        /// Run the resource example body through the plain lexical surface.
        pub fn body(eff: anytype) anyerror![]const u8 {
            return resourceBody(eff);
        }
    });

    for (transcript.items[0..transcript.len]) |item| {
        try writer.print("{s}\n", .{item});
    }
    try writer.print("final={s}\n", .{result.value});
}

/// Run the resource-effect example.
pub fn main(init: std.process.Init) anyerror!void {
    var stdout_buffer: [512]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(init.io, &stdout_buffer);
    const stdout = &stdout_writer.interface;
    try run(stdout);
    try stdout.flush();
}
