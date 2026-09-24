const std = @import("std");
const b = @import("boundary");
test "foreign effect rejects in public package while local binding succeeds" {
    var first = b.computation.Builder.init(std.testing.allocator);
    defer first.deinit();
    var second = b.computation.Builder.init(std.testing.allocator);
    defer second.deinit();
    const left = try b.authoring.Context.init(&first);
    const right = try b.authoring.Context.init(&second);
    const lu = try left.scalar(void);
    const ru = try right.scalar(void);
    const foreign = try left.external("same", lu, lu);
    const local = try right.external("same", ru, ru);
    const entry = try right.function("entry", &.{}, ru, &.{local});
    const body = try right.body(entry);
    const payload = try body.constant(void, {});
    try std.testing.expectError(error.ForeignHandle, body.perform(foreign, payload));
    try right.define(entry, try body.ret(try body.perform(local, payload)));
    var compiled = try right.compile(std.testing.allocator, entry, ru);
    defer compiled.deinit();
}
