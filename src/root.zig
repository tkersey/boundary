const shared = @import("ability_shared");

/// Public lexical effect namespace.
pub const effect = shared.effect;
/// Canonical runtime handle for lexical execution.
pub const Runtime = shared.Runtime;
/// Public runtime misuse and semantic-contract errors surfaced by `ability`.
pub const RuntimeError = shared.RuntimeError;
/// Stable source-content hash helper for source-backed `ability.with` bodies.
pub const sourceHash = shared.sourceHash;
/// Run the public lexical handler entrypoint.
pub fn with(
    runtime: *Runtime,
    handlers: anytype,
    comptime Body: type,
) shared.WithFnReturnType(@TypeOf(handlers), Body) {
    return shared.with(runtime, handlers, Body);
}

test {
    _ = Runtime;
    _ = RuntimeError;
    _ = effect;
    _ = sourceHash;
    _ = with;
}
