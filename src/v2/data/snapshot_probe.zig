//! Test-only adapter for comparing the production snapshot codec with Lean.
//! This executable grants no program-relative graph or execution admission.
const std = @import("std");
const graph = @import("graph.zig");
const record = @import("record.zig");
const snapshot = @import("snapshot.zig");
const wire = @import("wire.zig");

pub fn main(init: std.process.Init) !void {
    var args = std.process.Args.Iterator.init(init.minimal.args);
    defer args.deinit();
    _ = args.skip();
    const mode = args.next() orelse return error.ExpectedMode;
    if (std.mem.eql(u8, mode, "tags")) {
        if (args.next() != null) return error.InvalidArguments;
        inline for (@typeInfo(graph.NodeTag).@"enum".fields) |field|
            try std.Io.File.stdout().writeStreamingAll(init.io, field.name ++ "\n");
        return;
    }
    const path = args.next() orelse return error.ExpectedInput;
    if (args.next() != null) return error.InvalidArguments;
    if (!std.mem.eql(u8, mode, "normalize") and !std.mem.eql(u8, mode, "admit"))
        return error.InvalidMode;
    var arena = std.heap.ArenaAllocator.init(init.gpa);
    defer arena.deinit();
    const a = arena.allocator();
    const input = try std.Io.Dir.cwd().readFileAlloc(init.io, path, a, .limited(64 * 1024 * 1024));
    const state = if (std.mem.eql(u8, mode, "admit")) blk: {
        const admitted = try snapshot.decodeGraph(a, input);
        break :blk admitted.state;
    } else blk: {
        var reader: wire.Reader = .{ .input = try wire.unframe(.pst, input) };
        const raw = try record.read(graph.State, &reader, a);
        try reader.finish();
        break :blk raw;
    };
    const emitted = try snapshot.emit(a, state, a, null);
    try std.Io.File.stdout().writeStreamingAll(init.io, emitted.bytes);
}
