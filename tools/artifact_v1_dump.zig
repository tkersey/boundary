const artifact = @import("shift_vm").artifact;
const std = @import("std");

/// Decode and print one ArtifactV1 file in readable text form.
pub fn main() anyerror!void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const args = try std.process.argsAlloc(allocator);
    if (args.len != 2) return error.InvalidArgs;

    const bytes = try std.fs.cwd().readFileAlloc(allocator, args[1], std.math.maxInt(usize));
    const disasm = try artifact.disasmAlloc(allocator, bytes);
    var stdout_buffer: [4096]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    const stdout = &stdout_writer.interface;
    try stdout.writeAll(disasm);
    try stdout.flush();
}
