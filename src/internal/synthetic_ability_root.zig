const shared = @import("ability_shared");
// zlinter-disable require_doc_comment - synthetic ability root is an internal generated-packet shim.

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
