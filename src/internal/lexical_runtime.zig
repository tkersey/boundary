const lowered_machine = @import("lowered_machine");
const with_api = @import("../with_api.zig");

pub const Runtime = lowered_machine.Runtime;
pub const RuntimeError = lowered_machine.RuntimeError;
pub const effect = @import("../effect/root.zig");

pub fn With(comptime HandlersType: type, comptime Body: type) type {
    return with_api.With(HandlersType, Body);
}

pub fn with(
    runtime: *Runtime,
    handlers: anytype,
    comptime Body: type,
) with_api.WithFnReturnType(@TypeOf(handlers), Body) {
    return with_api.with(runtime, handlers, Body);
}
