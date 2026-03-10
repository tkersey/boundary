const registry = @import("control_lab_registry");
const scenarios = @import("control_lab_scenarios");
const std = @import("std");

fn printUsage(writer: anytype) !void {
    try writer.writeAll(
        \\usage:
        \\  control_studio list
        \\  control_studio run <witness-id>
        \\
    );
    try writer.writeAll("available witnesses:\n");
    for (registry.witnesses) |witness| {
        try writer.print("  {s}\n", .{witness.witness_id});
    }
}

/// Run the dedicated control-studio CLI.
pub fn main() anyerror!void {
    const allocator = std.heap.page_allocator;
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    var stdout_buffer: [1024]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    const stdout = &stdout_writer.interface;

    if (args.len < 2) {
        try printUsage(stdout);
        try stdout.flush();
        return;
    }

    if (std.mem.eql(u8, args[1], "list")) {
        try scenarios.listWitnesses(stdout);
        try stdout.flush();
        return;
    }

    if (std.mem.eql(u8, args[1], "run")) {
        if (args.len != 3) {
            try printUsage(stdout);
            try stdout.flush();
            return;
        }
        try scenarios.runWitness(stdout, args[2]);
        try stdout.flush();
        return;
    }

    try printUsage(stdout);
    try stdout.flush();
}
