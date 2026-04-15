const shared = @import("shift_shared");

/// Public lexical effect namespace.
pub const effect = shared.effect;
/// Canonical runtime handle for lexical execution.
pub const Runtime = shared.Runtime;
/// Public runtime misuse and semantic-contract errors surfaced by `shift`.
pub const RuntimeError = shared.RuntimeError;
/// Canonical named lexical body helper for compiled `shift.with(...)`.
pub const NamedBody = shared.NamedBody;
/// Run the public lexical handler entrypoint.
pub const with = shared.with;
/// Run the public lexical handler entrypoint through an explicit caller-owned source witness.
pub const withOwnedSource = shared.withOwnedSource;

test {
    _ = Runtime;
    _ = RuntimeError;
    _ = effect;
    _ = NamedBody;
    _ = with;
    _ = withOwnedSource;
}
