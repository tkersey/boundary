const shared = @import("shift_shared");
const std = @import("std");

/// Public `Runtime` declaration.
pub const Runtime = shared.Runtime;
/// Public `RuntimeError` declaration.
pub const RuntimeError = shared.RuntimeError;
/// Canonical named lexical body helper for compiled witness-only `withAt(...)` calls.
pub const NamedBody = shared.NamedBody;
/// Public lexical effect namespace for internal witness-only helpers.
pub const effect = shared.effect;

/// Build the public With metadata type.
pub const With = shared.With;

/// Run the public lexical handler entrypoint.
pub fn with(
    comptime caller: std.builtin.SourceLocation,
    runtime: *Runtime,
    handlers: anytype,
    comptime Body: type,
) @TypeOf(withAt(caller, runtime, handlers, Body)) {
    return withAt(caller, runtime, handlers, Body);
}

/// Run the public lexical handler entrypoint with explicit caller provenance.
pub fn withAt(
    comptime caller: std.builtin.SourceLocation,
    runtime: *Runtime,
    handlers: anytype,
    comptime Body: type,
) @TypeOf(shared.withAt(caller, runtime, handlers, Body)) {
    return shared.withAt(caller, runtime, handlers, Body);
}
