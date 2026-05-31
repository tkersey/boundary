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

    const import = loaded.imports()[0];
    const valid_binding = Target.Module.ImportBinding{
        .world_port_id = import.world_port_id,
        .world_port_ref = import.world_port_ref,
        .payload_ref = import.payload_ref,
        .response_ref = import.response_ref,
        .mode = import.mode,
        .response_kind = import.response_kind,
    };
    const invalid_binding = Target.Module.ImportBinding{
        .world_port_id = import.world_port_id,
        .world_port_ref = import.world_port_ref,
        .payload_ref = import.response_ref,
        .response_ref = import.payload_ref,
    };

    const valid_report = loaded.checkImportBindings(&.{valid_binding});
    const invalid_report = loaded.checkImportBindings(&.{invalid_binding});

    try writer.print("world_port_id={d}\n", .{import.world_port_id});
    try writer.print("payload_value_ref={s}\n", .{import.payload_ref.codec});
    try writer.print("response_value_ref={s}\n", .{import.response_ref.codec});
    try writer.print("valid_binding_accepted={any}\n", .{valid_report.valid});
    try writer.print("invalid_binding_rejected={any}\n", .{!invalid_report.valid});
}

pub fn main(init: std.process.Init) !void {
    var stdout_buffer: [1024]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(init.io, &stdout_buffer);
    const stdout = &stdout_writer.interface;
    try run(stdout);
    try stdout.flush();
}
