const shift = @import("shift");
const std = @import("std");

const ResourceRow = shift.effects.resource([]const u8);

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
        return resource;
    }

    /// Release resources in the canonical LIFO order.
    pub fn release(resource: []const u8) void {
        transcript.items[transcript.len] = if (std.mem.eql(u8, resource, "a")) "release=a" else "release=b";
        transcript.len += 1;
    }
};

const ResourceProgram = struct {
    pub const Uses = shift.Uses(ResourceRow);

    /// Acquire and use two resources through the open-row scope.
    pub fn body(eff: anytype) ![]const u8 {
        const first = try eff.resource.acquire();
        transcript.note(if (std.mem.eql(u8, first, "a")) "use=a" else "use=b");

        const second = try eff.resource.acquire();
        transcript.note(if (std.mem.eql(u8, second, "a")) "use=a" else "use=b");

        return "done";
    }
};

/// Write the resource-effect transcript through the open-row front door.
pub fn run(writer: anytype) anyerror!void {
    var runtime = shift.Runtime.init(std.heap.page_allocator);
    defer runtime.deinit();
    resource_manager.next_index = 0;
    transcript.len = 0;

    const result = try shift.run(&runtime, shift.bind(ResourceProgram, .{
        .resource = shift.handlers.resource([]const u8, resource_manager),
    }));

    for (transcript.items[0..transcript.len]) |item| {
        try writer.print("{s}\n", .{item});
    }
    try writer.print("final={s}\n", .{result.value});
}

/// Run the resource-effect example.
pub fn main() anyerror!void {
    var stdout_buffer: [512]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    const stdout = &stdout_writer.interface;
    try run(stdout);
    try stdout.flush();
}
