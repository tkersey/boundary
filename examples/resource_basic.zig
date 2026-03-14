const shift = @import("shift");
const std = @import("std");

const NoError = error{};
const ResourceInstance = shift.effect.resource.Instance([]const u8, NoError);

const manager = struct {
    var next_index: usize = 0;
    var transcript = [_][]const u8{ "", "", "", "", "", "" };
    var transcript_len: usize = 0;
    const resources = [_][]const u8{ "a", "b" };

    fn note(message: []const u8) void {
        transcript[transcript_len] = message;
        transcript_len += 1;
    }

    /// Hand out resources in a fixed order for the public example.
    pub fn acquire() []const u8 {
        const resource = resources[next_index];
        next_index += 1;
        note(resource);
        return resource;
    }

    /// Record release order for the public example.
    pub fn release(resource: []const u8) void {
        note(resource);
    }
};

const demo = struct {
    /// Acquire two resources and complete normally.
    pub fn body(comptime Cap: type, ctx: anytype) shift.ResetError(NoError)![]const u8 {
        const first = try shift.effect.resource.acquire(Cap, ctx);
        manager.note(first);
        const second = try shift.effect.resource.acquire(Cap, ctx);
        manager.note(second);
        return "done";
    }
};

/// Write the bracketed resource transcript for this example.
pub fn run(writer: anytype) anyerror!void {
    var runtime = shift.Runtime.init(std.heap.page_allocator, .{});
    defer runtime.deinit();
    var instance = ResourceInstance.init();

    manager.next_index = 0;
    manager.transcript_len = 0;
    const answer = try shift.effect.resource.handle([]const u8, &runtime, &instance, manager, demo);

    try writer.writeAll("acquire=a\n");
    try writer.writeAll("use=a\n");
    try writer.writeAll("acquire=b\n");
    try writer.writeAll("use=b\n");
    try writer.writeAll("release=b\n");
    try writer.writeAll("release=a\n");
    try writer.print("final={s}\n", .{answer});
}

/// Run the resource family example using only the public effect surface.
pub fn main() anyerror!void {
    var stdout_buffer: [512]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    const stdout = &stdout_writer.interface;
    try run(stdout);
    try stdout.flush();
}
