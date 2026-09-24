//! Public-package client: all generated branching and interpretation is Program code.
const std = @import("std");
const boundary = @import("boundary");
const a = boundary.authoring;

pub const Application = struct {
    pub fn emit(raw: *boundary.computation.Builder) !boundary.computation.Module {
        const c = try a.Context.init(raw);
        const integer = try c.scalar(u64);
        const boolean = try c.scalar(bool);
        const unit = try c.scalar(void);
        const input = try c.record(&.{ .{ .name = "input", .schema = integer }, .{ .name = "offset", .schema = integer } });
        const lookup = try c.external("client/lookup", integer, integer);
        const question = try c.local("client/question", integer, integer, .linear);
        const capability = try c.capability(question);
        const callable = try c.callable(&.{}, integer, &.{question}, .{ .use = .reusable, .captures = &.{ integer, capability } });
        const twice = try c.twice(callable);
        const responder = try c.function("lookup responder", &.{.{ .name = "key", .schema = integer }}, integer, &.{lookup});
        const response = try c.body(responder);
        try c.define(responder, try response.ret(try response.perform(lookup, try response.parameter("key"))));
        const h = try c.responder(question, integer, responder, .{
            .mode = .deep,
            .use = .linear,
            .residual = &.{lookup},
            .captures = &.{ integer, input, capability, callable },
            .body_captures = &.{integer},
        });
        const entry = try c.function("entry", &.{ .{ .name = "choose", .schema = boolean }, .{ .name = "numbers", .schema = input } }, integer, &.{lookup});
        const body = try c.body(entry);
        const numbers = try body.parameter("numbers");
        const x = try body.field(numbers, "input");
        const offset = try body.field(numbers, "offset");
        const yes = try body.branch();
        const no = try body.branch();
        const handled = try c.handledSchema(h);
        const work = try c.functionFor("interpreted work", handled);
        const interpreted = try yes.closureBody(work);
        const cap = try interpreted.parameter("capability");
        const query = try c.functionFor("reusable question", callable);
        const query_body = try interpreted.closureBody(query);
        try c.define(query, try query_body.ret(try query_body.performLocal(question, cap, x)));
        const replies = try interpreted.call(twice, &.{.{ .name = "callable", .value = try interpreted.lambda(query, callable) }});
        const first_plus_offset = try interpreted.checkedAdd(try interpreted.field(replies, "first"), offset, try interpreted.constant(void, {}));
        const result = try interpreted.checkedAdd(first_plus_offset, try interpreted.field(replies, "second"), try interpreted.constant(void, {}));
        try c.define(work, try interpreted.ret(result));
        const true_result = try yes.handleWith(h, try yes.lambda(work, handled), &.{});
        const false_result = try no.checkedAdd(x, offset, try no.constant(void, {}));
        const joined = try body.conditional(try body.parameter("choose"), try yes.ret(true_result), try no.ret(false_result));
        try c.define(entry, try body.ret(joined));
        return c.module(entry, unit);
    }
};
pub fn main(init: std.process.Init) !void {
    var compiled = try boundary.program.lower(init.gpa, Application);
    defer compiled.deinit();
    const bytes = try init.gpa.alloc(u8, try boundary.data.program_image.encodedLength(compiled.program));
    defer init.gpa.free(bytes);
    _ = try compiled.encode(init.gpa, bytes);
    var buffer: [4096]u8 = undefined;
    var output = std.Io.File.stdout().writer(init.io, &buffer);
    try output.interface.writeAll(bytes);
    try output.interface.flush();
}
