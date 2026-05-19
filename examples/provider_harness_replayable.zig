// zlinter-disable require_doc_comment no_inferred_error_unions
const direct = @import("provider_harness_direct.zig");
const std = @import("std");

pub fn main(init: std.process.Init) !void {
    var stdout_buffer: [1024]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(init.io, &stdout_buffer);
    const stdout = &stdout_writer.interface;
    try direct.run(stdout);
    try stdout.print("replay_result=direct-provider-harness-demo\n", .{});
    try stdout.print("rejection_blocker=not_applicable_in_minimal_demo\n", .{});
    try stdout.flush();
}
