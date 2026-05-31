// zlinter-disable declaration_naming require_doc_comment no_hidden_allocations no_inferred_error_unions
const fixture = @import("world_surface_ports.zig");
const std = @import("std");

const Target = fixture.Target;

pub fn run(writer: anytype) !void {
    const allocator = std.heap.page_allocator;
    const bytes = try Target.Module.fullImage(allocator);
    defer allocator.free(bytes);

    var loaded = try Target.Module.decode(allocator, bytes);
    defer loaded.deinit();

    try writer.print("module_fingerprint={x}\n", .{loaded.moduleFingerprint()});
    try writer.print("module_kind={s}\n", .{@tagName(loaded.kind())});
    try writer.print("world_surface_fingerprint={x}\n", .{loaded.worldSurfaceFingerprint()});
    try writer.print("normal_form_kind={s}\n", .{@tagName(loaded.normalFormKind())});
    try writer.print("required_import_count={d}\n", .{loaded.requiredImports().len});
    try writer.print("main_export_result_ref={s}\n", .{loaded.resultValueRef().codec});
}

pub fn main(init: std.process.Init) !void {
    var stdout_buffer: [1024]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(init.io, &stdout_buffer);
    const stdout = &stdout_writer.interface;
    try run(stdout);
    try stdout.flush();
}
