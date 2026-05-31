// zlinter-disable declaration_naming require_doc_comment no_hidden_allocations no_inferred_error_unions
const fixture = @import("world_surface_ports.zig");
const std = @import("std");

const Target = fixture.Target;

pub fn run(writer: anytype) !void {
    const allocator = std.heap.page_allocator;
    const bytes = try Target.Module.fullImage(allocator);
    defer allocator.free(bytes);

    var corrupt = try allocator.dupe(u8, bytes);
    defer allocator.free(corrupt);
    corrupt[corrupt.len - 1] ^= 0x1;

    const report = Target.Module.validationReport(corrupt, .{});
    const diagnostic = report.diagnosticSlice()[0];

    try writer.print("valid={any}\n", .{report.valid});
    try writer.print("section_kind={s}\n", .{if (diagnostic.section_kind) |kind| @tagName(kind) else "none"});
    try writer.print("error_tag={s}\n", .{if (diagnostic.error_tag) |tag| @errorName(tag) else "none"});
    try writer.print("expected_fingerprint={x}\n", .{diagnostic.expected_fingerprint orelse 0});
    try writer.print("actual_fingerprint={x}\n", .{diagnostic.actual_fingerprint orelse 0});
}

pub fn main(init: std.process.Init) !void {
    var stdout_buffer: [1024]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(init.io, &stdout_buffer);
    const stdout = &stdout_writer.interface;
    try run(stdout);
    try stdout.flush();
}
