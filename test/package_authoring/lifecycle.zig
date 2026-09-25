const std = @import("std");
const boundary = @import("boundary");
pub fn main(init: std.process.Init) !void {
    var raw = boundary.computation.Builder.init(init.gpa);
    defer raw.deinit();
    const c = try boundary.authoring.Context.init(&raw);
    const unit = try c.scalar(void);
    const entry = try c.function("closed", &.{}, unit, &.{});
    const body = try c.body(entry);
    try c.define(entry, try body.ret(try body.constant(void, {})));
    body.scope.active = true;
}
