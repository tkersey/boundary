// zlinter-disable declaration_naming require_doc_comment no_hidden_allocations no_inferred_error_unions
const boundary = @import("boundary");
const fixture = @import("world_surface_ports.zig");
const std = @import("std");

const Program = fixture.Program;
const Target = fixture.Target;

fn runLocalGeneratedTarget(allocator: std.mem.Allocator) !i32 {
    var runtime = boundary.Runtime.init(allocator);
    defer runtime.deinit();
    var session = try Program.Session.start(&runtime, .{});
    defer session.deinit();

    const request = switch (try session.next()) {
        .request => |value| value,
        .after => return error.UnexpectedAfter,
        .done => return error.UnexpectedDone,
    };
    const world_port_id = Target.WorldDispatchTable.lookup(request.operation_site_index) orelse return error.MissingWorldPort;
    if (world_port_id != 0) return error.UnexpectedWorldPort;
    try session.@"resume"(request, @as(i32, 7));

    var done = switch (try session.next()) {
        .done => |value| value,
        .request => return error.UnexpectedRequest,
        .after => return error.UnexpectedAfter,
    };
    defer done.deinit();
    return done.value;
}

pub fn run(writer: anytype) !void {
    const allocator = std.heap.page_allocator;
    const bytes = try Target.Module.fullImage(allocator);
    defer allocator.free(bytes);
    var loaded = try Target.Module.decode(allocator, bytes);
    defer loaded.deinit();

    var loaded_session = Target.Module.LoadedModule.Session.start(&loaded);
    const loaded_status: []const u8 = if (loaded_session.next()) |_| "unexpected_ready" else |err| switch (err) {
        error.UnsupportedLoadedExecution => "unsupported_fail_closed",
    };
    const final = try runLocalGeneratedTarget(allocator);

    try writer.print("loaded_session={s}\n", .{loaded_status});
    try writer.print("world_port_id={d}\n", .{loaded.imports()[0].world_port_id});
    try writer.print("request_site_fingerprint={x}\n", .{loaded.imports()[0].residual_site_fingerprint});
    try writer.print("local_generated_final_result={d}\n", .{final});
}

pub fn main(init: std.process.Init) !void {
    var stdout_buffer: [1024]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(init.io, &stdout_buffer);
    const stdout = &stdout_writer.interface;
    try run(stdout);
    try stdout.flush();
}
