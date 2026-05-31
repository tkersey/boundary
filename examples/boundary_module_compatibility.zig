// zlinter-disable declaration_naming require_doc_comment no_hidden_allocations no_inferred_error_unions
const fixture = @import("world_surface_ports.zig");
const std = @import("std");

const Target = fixture.Target;

pub fn run(writer: anytype) !void {
    const allocator = std.heap.page_allocator;
    const reference = try Target.Module.reference(allocator);
    defer allocator.free(reference);

    var corrupted = try allocator.dupe(u8, reference);
    defer allocator.free(corrupted);
    corrupted[0] = 'X';

    try Target.Module.validateReferenceAgainst(reference);
    const matching = Target.Module.referenceSummaryForBytes(reference);
    const valid_compatibility = Target.Module.compatibility(reference, .{ .allow_reference_only = true });
    const invalid_compatibility = Target.Module.compatibility(corrupted, .{ .allow_reference_only = true });

    try writer.print("matching_reference={any}\n", .{matching.compatible()});
    try writer.print("valid_compatible={any}\n", .{valid_compatibility.compatible});
    try writer.print("invalid_compatible={any}\n", .{invalid_compatibility.compatible});
    try writer.print("invalid_blockers={d}\n", .{invalid_compatibility.blocker_count});
}

pub fn main(init: std.process.Init) !void {
    var stdout_buffer: [1024]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(init.io, &stdout_buffer);
    const stdout = &stdout_writer.interface;
    try run(stdout);
    try stdout.flush();
}
