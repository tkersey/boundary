const lowered_machine = @import("lowered_machine");
const with_api = @import("../with_api.zig");

/// Return the public run result type.
pub fn RunReturnType(comptime HandlersType: type, comptime Body: type) type {
    return with_api.WithFnReturnType(HandlersType, Body);
}

/// Run this public entrypoint.
pub fn run(
    runtime: *lowered_machine.Runtime,
    handlers: anytype,
    comptime Body: type,
) with_api.WithFnReturnType(@TypeOf(handlers), Body) {
    return with_api.with(runtime, handlers, Body);
}
