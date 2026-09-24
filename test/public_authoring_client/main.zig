//! A package-only client combining named data, runtime control, reusable calls,
//! and a local interpretation with a residual external lookup.
const std = @import("std");
const boundary = @import("boundary");
const a = boundary.authoring;

pub const Application = struct {
    pub fn emit(author: *a.Builder) !a.Module {
        const integer = try author.scalar(u64);
        const boolean = try author.scalar(bool);
        const unit = try author.scalar(void);
        const input_record = try author.record(&.{
            .{ .name = "input", .schema = integer },
            .{ .name = "offset", .schema = integer },
        });
        const replies = try author.record(&.{
            .{ .name = "first", .schema = integer },
            .{ .name = "second", .schema = integer },
        });
        const question = try author.local("client/question", integer, integer, .linear);
        const lookup = try author.external("client/lookup", integer, integer);
        const capability = try author.capability(question);
        const failure = try author.literal(void, {});

        const responder = try author.declare("lookup responder", &.{
            .{ .name = "key", .schema = integer },
        }, integer, &.{lookup});
        var responder_body = try author.body(responder);
        const reply = try responder_body.perform(lookup, try responder_body.parameter("key"));
        try author.define(responder, try responder_body.finish(reply));
        const interpretation = try author.responding(question, responder, replies.schema, &.{lookup}, &.{ integer, capability, replies.schema }, .deep, .linear);

        const ask = try author.declare("ask once", &.{
            .{ .name = "question", .schema = capability },
            .{ .name = "key", .schema = integer },
            .{ .name = "offset", .schema = integer },
        }, integer, &.{question});
        var ask_body = try author.body(ask);
        const local_reply = try ask_body.performLocal(question, try ask_body.parameter("question"), try ask_body.parameter("key"));
        const adjusted = try ask_body.checkedAdd(local_reply, try ask_body.parameter("offset"), failure);
        try author.define(ask, try ask_body.finish(adjusted));

        const twice = try author.declare("apply twice", &.{
            .{ .name = "question", .schema = capability },
            .{ .name = "key", .schema = integer },
            .{ .name = "offset", .schema = integer },
        }, replies.schema, &.{question});
        var twice_body = try author.body(twice);
        const callable = try twice_body.lambda(ask, &.{}, .reusable);
        const arguments = &.{ try twice_body.parameter("question"), try twice_body.parameter("key"), try twice_body.parameter("offset") };
        const first = try twice_body.apply(callable, arguments);
        const second = try twice_body.apply(callable, arguments);
        const pair = try twice_body.product(replies, &.{
            .{ .name = "first", .value = first },
            .{ .name = "second", .value = second },
        });
        try author.define(twice, try twice_body.finish(pair));

        const entry = try author.declare("main", &.{
            .{ .name = "use_effect", .schema = boolean },
            .{ .name = "record", .schema = input_record.schema },
        }, integer, &.{lookup});
        var body = try author.body(entry);
        const record = try body.parameter("record");
        const input = try body.field(input_record, record, "input");
        const offset = try body.field(input_record, record, "offset");
        var yes = try body.child("effectful branch");
        const twice_callable = try yes.lambda(twice, &.{}, .reusable);
        const handled = try yes.handle(interpretation, twice_callable, &.{ input, offset }, &.{});
        const total = try yes.checkedAdd(try yes.field(replies, handled, "first"), try yes.field(replies, handled, "second"), failure);
        var no = try body.child("pure branch");
        const pure = try no.checkedAdd(input, offset, failure);
        const selected = try body.select(try body.parameter("use_effect"), try yes.finish(total), try no.finish(pure));
        try author.define(entry, try body.finish(selected));
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

test "foreign nominal capability and escaped branch value reject" {
    var raw = boundary.computation.Builder.init(std.testing.allocator);
    defer raw.deinit();
    var author = a.Builder.init(&raw);
    const integer = try author.scalar(u64);
    const question = try author.local("same name", integer, integer, .linear);
    const foreign = try author.local("same name", integer, integer, .linear);
    const foreign_cap = try author.capability(foreign);
    const entry = try author.declare("negative", &.{
        .{ .name = "cap", .schema = foreign_cap },
    }, integer, &.{question});
    var body = try author.body(entry);
    try std.testing.expectError(error.InvalidCapability, body.performLocal(question, try body.parameter("cap"), try author.literal(u64, 1)));
    try std.testing.expectEqual(a.Category.capability_mismatch, author.diagnostic.?.category);
    var branch = try body.child("branch");
    const local = try branch.checkedAdd(try author.literal(u64, 1), try author.literal(u64, 2), try author.literal(void, {}));
    _ = try branch.finish(local);
    try std.testing.expectError(error.OutOfScope, body.finish(local));
}
