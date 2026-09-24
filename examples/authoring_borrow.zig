//! Checked owned resource introduction, borrow, protected use, and disposal.
const std = @import("std");
const boundary = @import("boundary");
const a = boundary.authoring;

pub const Application = struct {
    pub fn emit(author: *a.Builder) !a.Module {
        const integer = try author.scalar(u64);
        const unit = try author.scalar(void);
        const representation = try author.record(&.{
            .{ .name = "value", .schema = integer },
        });
        const owned = try author.resource(representation.schema);
        const loan = author.region();
        const borrowed = try author.borrowedSchema(owned, loan);
        const exit_info = try author.exitInfo(unit);

        const acquire = try author.declare("acquire", &.{}, owned, &.{});
        const read = try author.declareScoped("read borrowed", &.{
            .{ .name = "borrowed", .schema = borrowed },
        }, integer, &.{}, &.{loan});
        const release = try author.declare("release", &.{
            .{ .name = "owned", .schema = owned },
        }, unit, &.{});
        try author.resourceAuthority(owned, &.{acquire}, &.{ read, release });
        var acquire_body = try author.body(acquire);
        const resource_value = try acquire_body.packResource(owned, try acquire_body.product(representation, &.{
            .{ .name = "value", .value = try author.literal(u64, 41) },
        }));
        try author.define(acquire, try acquire_body.finish(resource_value));
        var read_body = try author.body(read);
        const extracted = try read_body.unpackResource(try read_body.parameter("borrowed"));
        try author.define(read, try read_body.finish(try read_body.field(representation, extracted, "value")));
        var release_body = try author.body(release);
        _ = try release_body.bindValue(try release_body.unpackResource(try release_body.parameter("owned")));
        try author.define(release, try release_body.finish(try author.literal(void, {})));

        const work = try author.declareScoped("protected work", &.{
            .{ .name = "borrowed", .schema = borrowed },
        }, integer, &.{}, &.{loan});
        var work_body = try author.body(work);
        const value = try work_body.call(read, &.{try work_body.parameter("borrowed")});
        try author.define(work, try work_body.finish(value));
        const cleanup = try author.declare("cleanup", &.{
            .{ .name = "exit", .schema = exit_info },
            .{ .name = "owned", .schema = owned },
        }, unit, &.{});
        var cleanup_body = try author.body(cleanup);
        const cleaned = try cleanup_body.call(release, &.{try cleanup_body.parameter("owned")});
        try author.define(cleanup, try cleanup_body.finish(cleaned));

        const entry = try author.declare("main", &.{}, integer, &.{});
        var body = try author.body(entry);
        const resource = try body.call(acquire, &.{});
        const protected = try body.protect(try body.lambda(work, &.{}, .reusable), try body.lambda(cleanup, &.{}, .reusable), &.{}, resource, loan);
        try author.define(entry, try body.finish(protected));
        return author.module(entry, unit);
    }
};

pub fn main(init: std.process.Init) !void {
    var compiled = try a.lower(init.gpa, Application);
    defer compiled.deinit();
    const bytes = try init.gpa.alloc(u8, try boundary.data.program_image.encodedLength(compiled.program));
    defer init.gpa.free(bytes);
    _ = try compiled.encode(init.gpa, bytes);
    var buffer: [4096]u8 = undefined;
    var output = std.Io.File.stdout().writer(init.io, &buffer);
    try output.interface.writeAll(bytes);
    try output.interface.flush();
}
