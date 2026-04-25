const shared = @import("ability_shared");

/// Public lexical effect namespace.
pub const effect = shared.effect;
/// Canonical runtime handle for lexical execution.
pub const Runtime = shared.Runtime;
/// Public runtime misuse and semantic-contract errors surfaced by `ability`.
pub const RuntimeError = shared.RuntimeError;
/// Run the public lexical handler entrypoint.
pub fn with(
    runtime: *Runtime,
    handlers: anytype,
    comptime Body: type,
) shared.WithFnReturnType(@TypeOf(handlers), Body) {
    return shared.with(runtime, handlers, Body);
}

/// Run the public lexical handler entrypoint with caller-owned source bytes.
pub fn withCallerSource(
    comptime caller: @import("std").builtin.SourceLocation,
    comptime caller_source: []const u8,
    runtime: *Runtime,
    handlers: anytype,
    comptime Body: type,
) shared.WithFnReturnType(@TypeOf(handlers), Body) {
    return shared.withCallerSource(caller, caller_source, runtime, handlers, Body);
}

test {
    _ = Runtime;
    _ = RuntimeError;
    _ = effect;
    _ = with;
    _ = withCallerSource;
}
