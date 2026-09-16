// Copyright (c) 2026 Boundary contributors. MIT license.
//! This executable imports pure data only: no source compiler or emitter.
const std = @import("std");
const data = @import("boundary_data_v2");
const Manifest = struct {
    instances: []const struct { key: []const u8, path: []const u8 },
    bindings: []const data.linker.Binding,
    entry: data.linker.Endpoint,
};

pub fn main(init: std.process.Init) !void {
    var args = std.process.Args.Iterator.init(init.minimal.args);
    _ = args.next();
    const path = args.next() orelse return error.MissingManifest;
    if (args.next() != null) return error.UnexpectedArgument;
    var buffer: [4096]u8 = undefined;
    var output = std.Io.File.stdout().writer(init.io, &buffer);
    if (std.mem.eql(u8, path, "--help")) {
        try output.interface.writeAll("Usage: boundary-link MANIFEST.json > PROGRAM.bpi3\nBMO1 instance paths are relative to the current directory.\n");
        try output.interface.flush();
        return;
    }
    var arena = std.heap.ArenaAllocator.init(init.gpa);
    defer arena.deinit();
    const a = arena.allocator();
    const bytes = try std.Io.Dir.cwd().readFileAlloc(init.io, path, a, .limited(4 << 20));
    const manifest = try std.json.parseFromSlice(Manifest, a, bytes, .{ .allocate = .alloc_always });
    defer manifest.deinit();
    const instances = try a.alloc(data.linker.Instance, manifest.value.instances.len);
    for (instances, manifest.value.instances) |*instance, item| instance.* = .{
        .key = item.key,
        .object = try std.Io.Dir.cwd().readFileAlloc(init.io, item.path, a, .limited(64 << 20)),
    };
    var linked = try data.linker.link(init.gpa, instances, manifest.value.bindings, manifest.value.entry);
    defer linked.deinit();
    const image = try a.alloc(u8, try data.program_image.encodedLength(linked.program));
    _ = try linked.encode(init.gpa, image);
    try output.interface.writeAll(image);
    try output.interface.flush();
}
