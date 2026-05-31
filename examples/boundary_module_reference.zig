// zlinter-disable declaration_naming require_doc_comment no_hidden_allocations no_inferred_error_unions
const boundary = @import("boundary");
const fixture = @import("world_surface_ports.zig");
const std = @import("std");

const Target = fixture.Target;

pub fn run(writer: anytype) !void {
    const allocator = std.heap.page_allocator;
    const bytes = try Target.Module.reference(allocator);
    defer allocator.free(bytes);

    const report = try Target.Module.validate(bytes, .{ .allow_reference_only = true });
    try Target.Module.validateReferenceAgainst(bytes);

    try writer.print("module_kind={s}\n", .{@tagName(report.module_kind)});
    try writer.print("module_fingerprint={x}\n", .{report.module_fingerprint});
    try writer.print("target_certificate_fingerprint={x}\n", .{Target.Certificate.certificate_fingerprint});
    try writer.print("world_surface_fingerprint={x}\n", .{Target.WorldSurface.surface_fingerprint});
    try writer.print("program_plan_hash={x}\n", .{Target.Program.compiled_plan.hash()});
    try writer.print("reference_bytes={d}\n", .{bytes.len});
    _ = boundary;
}

pub fn main(init: std.process.Init) !void {
    var stdout_buffer: [1024]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(init.io, &stdout_buffer);
    const stdout = &stdout_writer.interface;
    try run(stdout);
    try stdout.flush();
}
