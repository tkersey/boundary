//! Equal Zig configuration types with different values produce distinct bodies.
const std = @import("std");
const boundary = @import("boundary");
const a = boundary.authoring;
const Setting = struct { increment: u64 };

fn configured(author: *a.Builder, integer: a.Schema, failure: a.FailureLiteral, setting: Setting) !a.Function {
    const function = try author.declare("configured", &.{
        .{ .name = "input", .schema = integer },
    }, integer, &.{});
    var body = try author.body(function);
    const result = try body.checkedAdd(try body.parameter("input"), try author.literal(u64, setting.increment), failure);
    try author.define(function, try body.finish(result));
    return function;
}

pub const Application = struct {
    pub fn emit(author: *a.Builder) !a.Module {
        const integer = try author.scalar(u64);
        const failure = try author.literalFailure(void, {});
        const one = try configured(author, integer, failure, Setting{ .increment = 1 });
        const two = try configured(author, integer, failure, Setting{ .increment = 2 });
        const result = try author.record(&.{
            .{ .name = "first", .schema = integer },
            .{ .name = "second", .schema = integer },
            .{ .name = "reused", .schema = integer },
        });
        const entry = try author.declare("main", &.{
            .{ .name = "input", .schema = integer },
        }, result.schema, &.{});
        var body = try author.body(entry);
        const input = try body.parameter("input");
        const first = try body.call(one, &.{input});
        const second = try body.call(two, &.{input});
        const reused = try body.call(one, &.{input});
        const output = try body.product(result, &.{
            .{ .name = "first", .value = first },
            .{ .name = "second", .value = second },
            .{ .name = "reused", .value = reused },
        });
        try author.define(entry, try body.finish(output));
        return author.module(entry, try author.scalar(void));
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
