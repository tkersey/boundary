// zlinter-disable declaration_naming require_doc_comment no_hidden_allocations no_inferred_error_unions
const fixture = @import("world_surface_ports.zig");
const std = @import("std");

const Target = fixture.Target;

pub fn run(writer: anytype) !void {
    const allocator = std.heap.page_allocator;
    const bytes = try Target.Module.fullImage(allocator);
    defer allocator.free(bytes);

    const report = try Target.Module.validate(bytes, .{ .require_full_module = true });
    var loaded = try Target.Module.decode(allocator, bytes);
    defer loaded.deinit();

    try writer.print("module_kind={s}\n", .{@tagName(report.module_kind)});
    try writer.print("module_fingerprint={x}\n", .{report.module_fingerprint});
    try writer.print("manifest_fingerprint={x}\n", .{loaded.manifest().manifest_fingerprint});
    try writer.print("world_surface_fingerprint={x}\n", .{loaded.manifest().world_surface_fingerprint});
    try writer.print("world_port_count={d}\n", .{loaded.manifest().world_port_count});
    try writer.print("import_count={d}\n", .{loaded.imports().len});
    try writer.print("export_result_codec={s}\n", .{loaded.exportMain().result_ref.codec});
    try writer.print("full_module_bytes={d}\n", .{bytes.len});
}

pub fn main(init: std.process.Init) !void {
    var stdout_buffer: [1024]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(init.io, &stdout_buffer);
    const stdout = &stdout_writer.interface;
    try run(stdout);
    try stdout.flush();
}
