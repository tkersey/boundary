const lowered_machine = @import("lowered_machine");
const with_api = @import("../with_api.zig");

/// Public `Runtime` declaration.
pub const Runtime = lowered_machine.Runtime;
/// Public `RuntimeError` declaration.
pub const RuntimeError = lowered_machine.RuntimeError;
/// Public `effect` declaration.
pub const effect = @import("../effect/root.zig");

/// Build the public With metadata type.
pub fn With(comptime HandlersType: type, comptime Body: type) type {
    return with_api.With(HandlersType, Body);
}

/// Run the public lexical handler entrypoint.
pub fn with(
    runtime: *Runtime,
    handlers: anytype,
    comptime Body: type,
) with_api.WithFnReturnType(@TypeOf(handlers), Body) {
    return with_api.with(runtime, handlers, Body);
}
