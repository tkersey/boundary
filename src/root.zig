const shared = @import("shift_shared");

/// Public lexical effect namespace.
pub const effect = shared.effect;
/// Canonical runtime handle for lexical execution.
pub const Runtime = shared.Runtime;
/// Public runtime misuse and semantic-contract errors surfaced by `shift`.
pub const RuntimeError = shared.RuntimeError;
/// Run the public lexical handler entrypoint.
pub fn with(
    runtime: *Runtime,
    handlers: anytype,
    comptime Body: type,
) shared.WithFnReturnType(@TypeOf(handlers), Body) {
    return shared.with(runtime, handlers, Body);
}
/// Test-only anonymous-body lowering helper for parity probes.
pub const debug_anonymous_body_synthesis = shared.debug_anonymous_body_synthesis;

test {
    _ = Runtime;
    _ = RuntimeError;
    _ = effect;
    _ = with;
    _ = debug_anonymous_body_synthesis;
}
