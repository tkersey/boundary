const lowered_machine = @import("lowered_machine");
const with_api = @import("../with_api.zig");

pub fn RunReturnType(comptime HandlersType: type, comptime Body: type) type {
    return with_api.WithFnReturnType(HandlersType, Body);
}

pub fn run(
    runtime: *lowered_machine.Runtime,
    handlers: anytype,
    comptime Body: type,
) with_api.WithFnReturnType(@TypeOf(handlers), Body) {
    return with_api.with(runtime, handlers, Body);
}
