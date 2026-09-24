//! Local cleanup remains installed across an external suspension.
const std = @import("std");
const boundary = @import("boundary");

pub const Application = struct {
    pub fn emit(a: *boundary.authoring.Builder) !boundary.authoring.Module {
        const integer = try a.scalar(u64);
        const unit = try a.scalar(void);
        const read = try a.external("authoring/protect/read", unit, integer);
        const release = try a.external("authoring/protect/release", integer, unit);
        const exit_info = try a.exitInfo(unit);
        const work = try a.declare("protected work", &.{}, integer, &.{read});
        var work_body = try a.body(work);
        const acquired = try work_body.perform(read, try a.literal(void, {}));
        try a.define(work, try work_body.finish(acquired));
        const cleanup = try a.declare("local cleanup", &.{
            .{ .name = "exit", .schema = exit_info },
        }, unit, &.{release});
        var cleanup_body = try a.body(cleanup);
        const disposed = try cleanup_body.perform(release, try a.literal(u64, 7));
        try a.define(cleanup, try cleanup_body.finish(disposed));
        const entry = try a.declare("main", &.{}, integer, &.{ read, release });
        var body = try a.body(entry);
        const protected = try body.protect(try body.lambda(work, &.{}, .reusable), try body.lambda(cleanup, &.{}, .reusable), &.{}, null, null);
        try a.define(entry, try body.finish(protected));
        return a.module(entry, unit);
    }
};

pub fn main(init: std.process.Init) !void {
    var compiled = try boundary.authoring.lower(init.gpa, Application);
    defer compiled.deinit();
    const bytes = try init.gpa.alloc(u8, try boundary.data.program_image.encodedLength(compiled.program));
    defer init.gpa.free(bytes);
    _ = try compiled.encode(init.gpa, bytes);
    var buffer: [4096]u8 = undefined;
    var output = std.Io.File.stdout().writer(init.io, &buffer);
    try output.interface.writeAll(bytes);
    try output.interface.flush();
}
