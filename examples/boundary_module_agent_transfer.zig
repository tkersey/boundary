// zlinter-disable declaration_naming require_doc_comment no_hidden_allocations no_inferred_error_unions
const boundary = @import("boundary");
const fixture = @import("world_surface_ports.zig");
const std = @import("std");

const Program = fixture.Program;
const Target = fixture.Target;

fn runLocalFixture(allocator: std.mem.Allocator) ![]const u8 {
    var runtime = boundary.Runtime.init(allocator);
    defer runtime.deinit();
    var session = try Program.Session.start(&runtime, .{});
    defer session.deinit();

    const request = switch (try session.next()) {
        .request => |value| value,
        .after => return error.UnexpectedAfter,
        .done => return error.UnexpectedDone,
    };
    try session.@"resume"(request, @as(i32, 7));
    var done = switch (try session.next()) {
        .done => |value| value,
        .request => return error.UnexpectedRequest,
        .after => return error.UnexpectedAfter,
    };
    defer done.deinit();
    return std.fmt.allocPrint(allocator, "approved:{d}", .{done.value});
}

fn runLoadedFixture(allocator: std.mem.Allocator, loaded: *Target.Module.LoadedModule) !i32 {
    var session = try Target.Module.LoadedModule.Session.startExecutable(
        allocator,
        loaded,
        Target.Module.LoadedExecutionProfile.portableV1(),
    );
    defer session.deinit();

    const request = switch (session.next()) {
        .request => |value| value,
        .failed => return error.UnexpectedLoadedFailure,
        .done => return error.UnexpectedLoadedDone,
    };
    const response = try Target.Module.LoadedExecution.encodeLoadedValueImageBytes(
        allocator,
        .{},
        .{ .codec = .i32 },
        .{ .i32 = 7 },
        .{},
    );
    defer allocator.free(response);
    try session.@"resume"(request, response);
    const done = switch (session.next()) {
        .done => |value| value,
        .request => return error.UnexpectedLoadedRequest,
        .failed => return error.UnexpectedLoadedFailure,
    };

    var value_arena = Target.Module.LoadedValueArena.init(allocator);
    defer value_arena.deinit();
    const decoded = try Target.Module.LoadedExecution.decodeLoadedValueImage(
        allocator,
        &value_arena,
        .{},
        .{ .codec = .i32 },
        done.canonical_result_image,
        .{},
    );
    return decoded.i32;
}

pub fn run(writer: anytype) !void {
    const allocator = std.heap.page_allocator;
    const bytes = try Target.Module.fullImage(allocator);
    defer allocator.free(bytes);
    var loaded = try Target.Module.decode(allocator, bytes);
    defer loaded.deinit();
    const final_text = try runLocalFixture(allocator);
    defer allocator.free(final_text);
    const loaded_result = try runLoadedFixture(allocator, &loaded);

    try writer.print("module_fingerprint={x}\n", .{loaded.manifest().module_fingerprint});
    try writer.print("model_import_count={d}\n", .{0});
    try writer.print("tool_import_count={d}\n", .{loaded.imports().len});
    try writer.print("tool_import_name={s}\n", .{loaded.imports()[0].suggested_symbolic_name});
    try writer.print("final_text={s}\n", .{final_text});
    try writer.print("loaded_final_result={d}\n", .{loaded_result});
}

test "agent-shaped module transfer generated loaded parity" {
    const allocator = std.testing.allocator;
    const bytes = try Target.Module.fullImage(allocator);
    defer allocator.free(bytes);
    var loaded = try Target.Module.decode(allocator, bytes);
    defer loaded.deinit();

    const final_text = try runLocalFixture(allocator);
    defer allocator.free(final_text);
    const loaded_result = try runLoadedFixture(allocator, &loaded);

    try std.testing.expectEqualStrings("approved:7", final_text);
    try std.testing.expectEqual(@as(i32, 7), loaded_result);
}

pub fn main(init: std.process.Init) !void {
    var stdout_buffer: [1024]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(init.io, &stdout_buffer);
    const stdout = &stdout_writer.interface;
    try run(stdout);
    try stdout.flush();
}
