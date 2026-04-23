const shared = @import("shift_shared");

/// Synthetic lexical-effect root used only by generated anonymous-body lowering packets.
pub const effect = shared.effect;
/// Synthetic runtime alias used by generated anonymous-body lowering packets.
pub const Runtime = shared.Runtime;
/// Synthetic runtime error alias used by generated anonymous-body lowering packets.
pub const RuntimeError = shared.RuntimeError;

pub fn with(
    runtime: *Runtime,
    handlers: anytype,
    comptime Body: type,
) shared.WithFnReturnType(@TypeOf(handlers), Body) {
    return shared.with(runtime, handlers, Body);
}
