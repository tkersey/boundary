const error_witness = @import("error_witness");
const lowered_machine = @import("lowered_machine");
const with_api = @import("../with_api.zig");

pub const Runtime = lowered_machine.Runtime;
pub const RuntimeError = lowered_machine.RuntimeError;
pub const ErrorWitnessV1 = error_witness.ErrorWitnessV1;
pub const algebraic = @import("../algebraic.zig");
pub const effect = @import("../effect/root.zig");
pub const ordinary = @import("../ordinary/root.zig");

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

test {
    _ = Runtime;
    _ = RuntimeError;
    _ = ErrorWitnessV1;
    _ = algebraic;
    _ = effect;
    _ = ordinary;
    _ = With;
    _ = with;
}
